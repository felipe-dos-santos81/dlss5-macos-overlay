import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import ScreenCore

struct VideoInfo: Sendable {
    let url: URL
    let size: FrameSize
    let duration: Double
    let frameRate: Double
    let hasAudio: Bool

    static func inspect(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PortError.message("This file does not contain a video track.")
        }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: natural).applying(transform).integral
        let rate = try await track.load(.nominalFrameRate)
        let formats = try await track.load(.formatDescriptions)
        for format in formats {
            guard let raw = CMFormatDescriptionGetExtensions(format) else { continue }
            let extensions = raw as NSDictionary
            let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
            if transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String ||
               transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String {
                throw PortError.message("HDR video is not supported yet. Convert this clip to SDR first.")
            }
        }
        guard duration.isFinite, duration > 0, bounds.width >= 2, bounds.height >= 2,
              bounds.width <= 16384, bounds.height <= 16384 else {
            throw PortError.message("The video has an unsupported duration or frame size.")
        }
        let size = FrameSize(Int(bounds.width), Int(bounds.height))
        guard size.width % 2 == 0, size.height % 2 == 0 else {
            throw PortError.message("MP4 export requires even frame dimensions. Resize this clip by one pixel first.")
        }
        return VideoInfo(url: url, size: size, duration: duration,
                         frameRate: rate.isFinite && rate > 0 ? Double(rate) : 30,
                         hasAudio: try await !asset.loadTracks(withMediaType: .audio).isEmpty)
    }
}

struct VideoProgress: @unchecked Sendable {
    let frame: RenderedFrame
    let count: Int
    let fraction: Double
    let elapsed: Double
}

struct VideoExportResult: Sendable {
    let url: URL
    let frames: Int
    let duration: Double
    let hasAudio: Bool
}

/// A private file in the destination directory keeps cancellation and failures
/// from destroying an existing export. Only a successful job replaces it.
struct VideoDestination {
    let url: URL
    let temporary: URL

    init(input: URL, output: URL) throws {
        guard output.isFileURL, output.pathExtension.lowercased() == "mp4" else {
            throw PortError.message("Choose a local MP4 file for the output.")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw PortError.message("The output must be a file, not a directory.")
        }
        guard input.resolvingSymlinksInPath().standardizedFileURL != output.resolvingSymlinksInPath().standardizedFileURL else {
            throw PortError.message("Choose a different output file. The original video cannot be overwritten.")
        }
        if let source = try? FileManager.default.attributesOfItem(atPath: input.path),
           let target = try? FileManager.default.attributesOfItem(atPath: output.path),
           let inode = source[.systemFileNumber] as? NSNumber,
           inode == target[.systemFileNumber] as? NSNumber,
           source[.systemNumber] as? NSNumber == target[.systemNumber] as? NSNumber {
            throw PortError.message("The output points to the original video. Choose a different file.")
        }
        url = output
        temporary = output.deletingLastPathComponent().appendingPathComponent(".dlss-export-\(UUID().uuidString).mp4")
    }
    func commit() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: url) }
    }
    func cleanUp() { try? FileManager.default.removeItem(at: temporary) }
}

private actor OfflineDecoder {
    let reader: AVAssetReader
    let provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>
    let transform: CGAffineTransform

    init(url: URL, audio: Bool) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: audio ? .audio : .video)
        guard let track = tracks.first else { throw PortError.message("The requested media track is missing.") }
        reader = try AVAssetReader(asset: asset)
        let output: AVAssetReaderOutput
        if audio {
            // Mix source audio tracks into one stereo AAC track; do not record
            // the microphone or sound from other applications.
            output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false])
            transform = .identity
        } else {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true])
            transform = try await track.load(.preferredTransform)
        }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw PortError.message("Cannot decode this media track.") }
        provider = reader.outputProvider(for: output)
        guard reader.startReading() else { throw reader.error ?? PortError.message("Cannot start the video decoder.") }
    }

    func next() async throws -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent>? {
        try Task.checkCancellation()
        let sample = try await provider.next()
        if sample == nil, reader.status == .failed { throw reader.error ?? PortError.message("Media decoding failed.") }
        return sample
    }
    func cancel() { reader.cancelReading() }
}

private actor OfflineEncoder {
    let writer: AVAssetWriter
    let video: AVAssetWriterInput.PixelBufferReceiver
    let audio: AVAssetWriterInput.SampleBufferReceiver?

    init(url: URL, info: VideoInfo, includeAudio: Bool) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: info.size.width, AVVideoHeightKey: info.size.height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(4_000_000, Int(Double(info.size.width * info.size.height) * info.frameRate * 0.20)),
                AVVideoExpectedSourceFrameRateKey: info.frameRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 2]]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw PortError.message("The H.264 encoder does not support this video size.")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        video = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        if includeAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256000])
            input.expectsMediaDataInRealTime = false
            audio = writer.inputReceiver(for: input)
        } else { audio = nil }
        guard writer.startWriting() else { throw writer.error ?? PortError.message("Cannot start MP4 export.") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ frame: RenderedFrame, at time: CMTime) async throws {
        try Task.checkCancellation()
        // Native async backpressure: every decoded frame waits for the encoder.
        try await video.append(CVReadOnlyPixelBuffer(unsafeBuffer: frame.pixels), with: time)
    }
    func appendAudio(_ sample: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) async throws {
        try Task.checkCancellation()
        try await audio?.append(sample)
    }
    func finishVideo() { video.finish() }
    func finishAudio() { audio?.finish() }
    func finish(at duration: Double) async throws {
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600000))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PortError.message("Could not finish the MP4 file.") }
    }
    func cancel() { if writer.status == .writing { writer.cancelWriting() } }
}

actor VideoProcessor {
    private let engine: RenderEngine
    init(engine: RenderEngine) { self.engine = engine }

    func export(input: URL, output: URL, settings: RenderSettings, includeAudio: Bool,
                progress: @escaping @Sendable (VideoProgress) async -> Void) async throws -> VideoExportResult {
        let destination = try VideoDestination(input: input, output: output)
        defer { destination.cleanUp() }
        let info = try await VideoInfo.inspect(input)
        try Task.checkCancellation()
        let video = try await OfflineDecoder(url: input, audio: false)
        let audio = info.hasAudio && includeAudio ? try await OfflineDecoder(url: input, audio: true) : nil
        let sink = try OfflineEncoder(url: destination.temporary, info: info, includeAudio: audio != nil)
        await engine.invalidateHistory()
        do {
            let count = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Int.self) { group in
                    group.addTask { try await self.processFrames(video, sink: sink, info: info, settings: settings, progress: progress) }
                    if let audio {
                        group.addTask {
                            while let sample = try await audio.next() { try await sink.appendAudio(sample) }
                            await sink.finishAudio()
                            return 0
                        }
                    }
                    var count = 0
                    do { for try await value in group { count += value } }
                    catch {
                        group.cancelAll()
                        await sink.cancel(); await video.cancel(); await audio?.cancel()
                        throw error
                    }
                    return count
                }
            } onCancel: {
                Task { await sink.cancel(); await video.cancel(); await audio?.cancel() }
            }
            try Task.checkCancellation()
            guard count > 0 else { throw PortError.message("The video contains no decodable frames.") }
            try await withTaskCancellationHandler {
                try await sink.finish(at: info.duration)
            } onCancel: { Task { await sink.cancel() } }
            try Task.checkCancellation()
            try destination.commit()
            await engine.invalidateHistory()
            return VideoExportResult(url: output, frames: count, duration: info.duration, hasAudio: audio != nil)
        } catch {
            await sink.cancel(); await video.cancel(); await audio?.cancel()
            await engine.invalidateHistory()
            throw error
        }
    }

    private func processFrames(_ decoder: OfflineDecoder, sink: OfflineEncoder, info: VideoInfo,
                               settings: RenderSettings,
                               progress: @escaping @Sendable (VideoProgress) async -> Void) async throws -> Int {
        let surfaces = try MetalFrames()
        let context = CIContext(mtlDevice: surfaces.device, options: [.cacheIntermediates: false])
        let transform = decoder.transform
        let colour = CGColorSpace(name: CGColorSpace.sRGB)!
        let begin = ProcessInfo.processInfo.systemUptime
        var count = 0
        var previous: CMTime?
        var lastReport = 0.0
        while let sample = try await decoder.next() {
            try Task.checkCancellation()
            let time = sample.presentationTimeStamp
            guard time.isNumeric, time >= .zero, previous.map({ time > $0 }) ?? true else {
                throw PortError.message("Video frame timestamps must be valid and increasing.")
            }
            guard case .pixelBuffer(let buffer) = sample.content else { throw PortError.message("The decoder returned an empty frame.") }
            let pixels: CVPixelBuffer = try buffer.withUnsafeBuffer { original in
                // Bake orientation into the pixels so the preview and export agree.
                let image = CIImage(cvPixelBuffer: original).transformed(by: transform)
                let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                let target = try surfaces.allocate(info.size)
                context.render(normalized, to: target,
                    bounds: CGRect(x: 0, y: 0, width: info.size.width, height: info.size.height), colorSpace: colour)
                return target
            }
            let result = try await engine.process(CapturedFrame(pixels: pixels, capturedAt: time.seconds), settings: settings)
            try await sink.append(result, at: time)
            previous = time; count += 1
            let now = ProcessInfo.processInfo.systemUptime
            if count == 1 || now - lastReport > 0.12 {
                let duration = sample.duration.isNumeric ? max(0, sample.duration.seconds) : 1 / info.frameRate
                await progress(VideoProgress(frame: result, count: count,
                    fraction: min(0.999, max(0, (time.seconds + duration) / info.duration)), elapsed: now - begin))
                lastReport = now
            }
        }
        await sink.finishVideo()
        return count
    }
}
