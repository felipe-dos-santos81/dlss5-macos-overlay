import Foundation
import CoreVideo
import DLSSCore
import DLSSMLX
import DLSSMedia
import ScreenCore

struct CapturedFrame: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let capturedAt: Double
}

struct RenderedFrame: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let capturedAt: Double
    let milliseconds: Double
    let processingSize: FrameSize
    let neural: Bool
}

actor RenderEngine {
    private let surfaces: MetalFrames
    private var renderer: MLXNeuralRenderingDeviceTemporalBackend?
    private var flow: NativeOpticalFlow?
    private var writer: MLXPixelBufferWriter?
    private var modelURL: URL?
    private var boundary: HistoryBoundary?
    private var index = 0
    private var streamID: UInt64 = 1
    private var lastTimestamp: Double = 0
    private var retainedResult: (timestamp: Double, boundary: HistoryBoundary, small: MLXPixelBuffer, processed: MLXPixelBuffer)?

    init() throws { surfaces = try MetalFrames() }

    func loadModel(_ url: URL) throws {
        let next = try MLXNeuralRenderingDeviceTemporalBackend(packageURL: url,
            executionMode: .metalFused, computePrecision: .float16)
        renderer = next; modelURL = url; invalidateHistory()
    }

    func invalidateHistory() {
        boundary = nil; flow = nil; writer = nil; retainedResult = nil
        index = 0; streamID &+= 1; lastTimestamp = 0
    }

    func process(_ frame: CapturedFrame, settings: RenderSettings) async throws -> RenderedFrame {
        let begin = ProcessInfo.processInfo.systemUptime
        let size = FrameSize(CVPixelBufferGetWidth(frame.pixels), CVPixelBufferGetHeight(frame.pixels))
        let work = size.processing(longEdge: settings.processingLongEdge)
        guard settings.neuralEnabled, settings.intensity > 0 else {
            invalidateHistory()
            return RenderedFrame(pixels: frame.pixels, capturedAt: frame.capturedAt,
                                 milliseconds: 0, processingSize: work, neural: false)
        }
        guard let renderer else { throw PortError.message("NR.dlss has not finished loading.") }
        let next = HistoryBoundary(size: work, settings: settings)
        if let retained = retainedResult, retained.timestamp == frame.capturedAt, retained.boundary == next {
            let output = try await surfaces.composite(original: frame.pixels, input: retained.small.buffer,
                                                       processed: retained.processed.buffer, split: settings.split)
            return RenderedFrame(pixels: output.buffer, capturedAt: frame.capturedAt,
                milliseconds: (ProcessInfo.processInfo.systemUptime - begin) * 1000, processingSize: work, neural: true)
        }
        if next != boundary || frame.capturedAt - lastTimestamp > 0.5 {
            invalidateHistory(); boundary = next
            writer = try MLXPixelBufferWriter(width: work.width, height: work.height, halfOutput: true)
            if settings.temporal { flow = try NativeOpticalFlow(width: work.width, height: work.height) }
        }
        lastTimestamp = frame.capturedAt
        let small = try await surfaces.resize(frame.pixels, to: work)
        let rgb = try MLXVideoFrame(pixelBuffer: small)
        let motion = try await flow?.prepare(rgb, index: index, sceneCutThreshold: 0.3)
        let profile = NeuralRenderingControlProfile(rawValue: settings.profile) ?? .natural
        let controls = NeuralRenderingFeatureControls(normalizedStyle: Float(profile.styleIndex) / 128,
            localToneStrength: settings.tone, localStructureStrength: settings.structure)
        let result = try await renderer.renderVideoFrame(rgb, motion: motion,
            context: NeuralRenderFrameContext(streamID: streamID, frameIndex: UInt64(index)),
            processingScale: 1, temporal: settings.temporal,
            outputOptions: MLXVideoOutputOptions(width: work.width, height: work.height,
                                                 detailStrength: 1, colourStrength: 1),
            featureControls: controls, intensity: settings.intensity)
        index += 1
        let processed = try await writer!.write(result)
        retainedResult = (frame.capturedAt, next, small, processed)
        let output = try await surfaces.composite(original: frame.pixels, input: small.buffer,
                                                 processed: processed.buffer, split: settings.split)
        return RenderedFrame(pixels: output.buffer, capturedAt: frame.capturedAt,
            milliseconds: (ProcessInfo.processInfo.systemUptime - begin) * 1000,
            processingSize: work, neural: true)
    }
}
