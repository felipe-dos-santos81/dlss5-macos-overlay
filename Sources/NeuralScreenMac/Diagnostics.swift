import AppKit
import SwiftUI
import Foundation
import CoreVideo
import AVFoundation
import DLSSMedia
import DLSSMLX
import ScreenCore

enum Diagnostics {
    static func argument(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }
    static func modelURL() throws -> URL {
        if let path = argument("--model") { return URL(fileURLWithPath: path) }
        return try BundledModel.url()
    }
    @MainActor static func run() async throws {
        let directory = URL(fileURLWithPath: argument("--output") ?? "/private/tmp/dlss-mac-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--video-test") {
            try await VideoDiagnostics.run(directory: directory, model: modelURL().path)
            return
        }
        if let input = argument("--process-video") {
            guard let output = argument("--video-output") else {
                throw PortError.message("--process-video requires --video-output FILE.")
            }
            let engine = try RenderEngine()
            try await engine.loadModel(modelURL())
            var settings = RenderSettings()
            settings.processingLongEdge = Int(argument("--width") ?? "512") ?? 512
            settings.sanitize()
            let result = try await VideoProcessor(engine: engine).export(input: URL(fileURLWithPath: input),
                output: URL(fileURLWithPath: output), settings: settings,
                includeAudio: !CommandLine.arguments.contains("--no-audio")) { update in
                    print("\(update.count) frames · \(Int(update.fraction * 100))%")
                }
            print("Exported \(result.frames) frames: \(result.url.path)")
            return
        }
        if CommandLine.arguments.contains("--ui-snapshot") {
            _ = NSApplication.shared
            let model = AppModel()
            if CommandLine.arguments.contains("--load-default-model") {
                await model.initialize(refreshCaptureSources: false)
                guard model.modelLoaded else { throw PortError.message(model.error ?? "Default model failed to load") }
                print("PASS NR.dlss loaded automatically from \(try BundledModel.url().path)")
            }
            if CommandLine.arguments.contains("--video-tab") { model.mode = .video }
            let host = NSHostingView(rootView: ControlsView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 820),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw PortError.message("Cannot render controls") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw PortError.message("Cannot encode controls preview") }
            try data.write(to: directory.appendingPathComponent("controls.png"))
            print("PASS native control view rendered to controls.png")
            return
        }
        if CommandLine.arguments.contains("--capture-test") {
            print("Capture diagnostic bundle: \(Bundle.main.bundleIdentifier ?? "unbundled executable")")
            let preflight = CGPreflightScreenCaptureAccess()
            print("Screen Recording preflight: \(preflight)")
            if !preflight && CommandLine.arguments.contains("--request-screen-permission") {
                print("Screen Recording request: \(CGRequestScreenCaptureAccess())")
            }
            // ScreenCaptureKit is the authoritative check; a preflight result
            // can lag behind a grant made while the process was running.
            let capture = ScreenCapture()
            guard let source = try await ScreenCapture.sources().first else { throw PortError.message("No displays available.") }
            let receiver = try await capture.start(source: source, fps: 15, onError: { print("capture error: \($0)") }, onAudio: { _ in })
            let timeout = Task { try? await Task.sleep(for: .seconds(10)); receiver.frames.finish() }
            let engine = try RenderEngine()
            var settings = RenderSettings()
            settings.neuralEnabled = !CommandLine.arguments.contains("--capture-only")
            if settings.neuralEnabled { try await engine.loadModel(modelURL()) }
            var received = 0
            for await captured in receiver.frames.stream {
                received += 1
                let result = try await engine.process(captured, settings: settings)
                print("Captured \(CVPixelBufferGetWidth(captured.pixels))x\(CVPixelBufferGetHeight(captured.pixels))")
                print("Processed: neural=\(result.neural), \(String(format: "%.2f", result.milliseconds)) ms")
                if received == 3 { break }
            }
            timeout.cancel(); await capture.stop()
            guard received > 0 else { throw PortError.message("Capture did not return any frames within 10 seconds.") }
            return
        }
        let surfaces = try MetalFrames()
        let size = FrameSize(960, 540)
        let input = try makePattern(surfaces, size: size, phase: 0)
        let small = try await surfaces.resize(input, to: FrameSize(512, 288))
        let identity = try await surfaces.composite(original: input, input: small.buffer, processed: small.buffer, split: 0)
        let identityError = difference(input, identity.buffer)
        guard identityError <= 1.0 / 255 else { throw PortError.message("Metal identity composite failed: \(identityError)") }
        try ImageExport.writePNG(input, to: directory.appendingPathComponent("original.png"))
        print("PASS Metal resize + identity residual composite; MAE=\(identityError)")

        let engine = try RenderEngine()
        var settings = RenderSettings(); settings.neuralEnabled = false
        let bypass = try await engine.process(CapturedFrame(pixels: input, capturedAt: ProcessInfo.processInfo.systemUptime), settings: settings)
        guard !bypass.neural, difference(input, bypass.pixels) == 0 else { throw PortError.message("Bypass altered the frame") }
        print("PASS bypass is pixel-identical")

        let record = Recording()
        let recordingURL = directory.appendingPathComponent("recording-\(UUID().uuidString).mp4")
        try await record.start(url: recordingURL, width: size.width, height: size.height, withAudio: true)
        let epoch = ProcessInfo.processInfo.systemUptime
        for i in 0..<12 {
            record.append(RenderedFrame(pixels: input, capturedAt: epoch + Double(i) / 30,
                milliseconds: 0, processingSize: size, neural: false))
            record.appendAudio(try makeAudio(at: epoch + Double(i) / 30))
            try await Task.sleep(for: .milliseconds(20))
        }
        try await record.stop()
        let asset = AVURLAsset(url: recordingURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        guard tracks.count == 1, audioTracks.count == 1, duration > 0.25 else { throw PortError.message("Recording validation failed") }
        print("PASS H.264 + AAC recording: \(String(format: "%.3f", duration)) seconds")

        try await engine.loadModel(modelURL())
        settings.neuralEnabled = true
        settings.temporal = !CommandLine.arguments.contains("--no-temporal")
        settings.processingLongEdge = Int(argument("--width") ?? "512") ?? 512
        let warmup = max(1, Int(argument("--warmup") ?? "6") ?? 6)
        let frames = max(warmup + 3, Int(argument("--frames") ?? "24") ?? 24)
        var measurements = [Double]()
        var last: RenderedFrame?
        var firstError = 0.0
        for i in 0..<frames {
            let moving = try makePattern(surfaces, size: size, phase: i * 2)
            let result = try await engine.process(CapturedFrame(pixels: moving, capturedAt: ProcessInfo.processInfo.systemUptime), settings: settings)
            if i == 0 { firstError = difference(moving, result.pixels) }
            if i >= warmup { measurements.append(result.milliseconds) }
            last = result
            print("frame \(i): \(String(format: "%.2f", result.milliseconds)) ms; neural=\(result.neural)")
            fflush(stdout)
        }
        guard firstError.isFinite, firstError > 0.00001, let last, last.neural else { throw PortError.message("Model produced no measurable effect") }
        try ImageExport.writePNG(last.pixels, to: directory.appendingPathComponent("processed.png"))
        settings.split = 1
        let allOriginal = try await engine.process(CapturedFrame(pixels: input, capturedAt: ProcessInfo.processInfo.systemUptime), settings: settings)
        guard difference(input, allOriginal.pixels) <= 1.0 / 255 else { throw PortError.message("Before/after split=1 altered original pixels") }
        let average = measurements.reduce(0, +) / Double(measurements.count)
        let report: [String: Any] = ["gpu": surfaces.device.name, "processingWidth": settings.processingLongEdge,
            "temporal": settings.temporal, "frames": frames, "warmupFrames": warmup,
            "source": "synthetic 960x540 translating pattern",
            "warmAverageMilliseconds": average, "warmProcessingFPS": 1000 / average,
            "firstFrameMAE": firstError, "identityMAE": identityError,
            "notes": "Includes downscale, optical flow, MLX NR and native composite; excludes capture and display. No NVIDIA parity assertion."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("benchmark.json"))
        print("PASS real MLX/Metal inference: \(String(format: "%.2f", 1000 / average)) FPS, MAE from input \(firstError)")
    }

    static func makeAudio(at timestamp: Double) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
            mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr, let format else {
            throw PortError.message("Audio format creation failed")
        }
        let angularStep = 440.0 * 2.0 * Double.pi / 48000.0
        let samples: [Float] = (0..<3200).map { i in Float(sin(Double(i / 2) * angularStep) * 0.1) }
        var block: CMBlockBuffer?
        let bytes = samples.count * MemoryLayout<Float>.size
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes,
            flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { throw PortError.message("Audio allocation failed") }
        let status = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        guard status == noErr else { throw PortError.message("Audio copy failed") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
            presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 600000), decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format,
            sampleCount: 1600, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer) == noErr, let buffer else {
            throw PortError.message("Audio sample creation failed")
        }
        return buffer
    }

    static func makePattern(_ surfaces: MetalFrames, size: FrameSize, phase: Int) throws -> CVPixelBuffer {
        let buffer = try surfaces.allocate(size)
        CVPixelBufferLockBaseAddress(buffer, []); defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<size.height { for x in 0..<size.width {
            let offset = y * stride + x * 4
            let shifted = (x + phase) % size.width
            base[offset] = UInt8(30 + y * 130 / size.height)
            base[offset + 1] = UInt8(20 + shifted * 180 / size.width)
            base[offset + 2] = UInt8(40 + ((shifted / 40 + y / 40) % 2) * 140)
            base[offset + 3] = 255
        } }
        return buffer
    }
    static func difference(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(a, .readOnly); CVPixelBufferLockBaseAddress(b, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(a, .readOnly); CVPixelBufferUnlockBaseAddress(b, .readOnly) }
        let ap = CVPixelBufferGetBaseAddress(a)!.assumingMemoryBound(to: UInt8.self)
        let bp = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(a), height = CVPixelBufferGetHeight(a)
        var total: Double = 0
        for y in 0..<height { for x in 0..<width { for c in 0..<3 {
            total += Double(abs(Int(ap[y * CVPixelBufferGetBytesPerRow(a) + x * 4 + c]) - Int(bp[y * CVPixelBufferGetBytesPerRow(b) + x * 4 + c])))
        } } }
        return total / Double(width * height * 3 * 255)
    }
}
