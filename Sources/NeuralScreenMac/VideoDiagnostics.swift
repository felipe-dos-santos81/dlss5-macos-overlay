import AVFoundation
import Foundation
import ScreenCore

enum VideoDiagnostics {
    static func run(directory: URL, model: String?) async throws {
        let input = directory.appendingPathComponent("fixture-\(UUID().uuidString).mp4")
        let portrait = directory.appendingPathComponent("portrait-\(UUID().uuidString).mp4")
        try await makeFixture(input, rotated: false)
        try await makeFixture(portrait, rotated: true)
        let original = try Data(contentsOf: input)
        let engine = try RenderEngine()
        if let model { try await engine.loadModel(URL(fileURLWithPath: model)) }
        let processor = VideoProcessor(engine: engine)
        var settings = RenderSettings(); settings.neuralEnabled = model != nil
        settings.processingLongEdge = 320
        let output = directory.appendingPathComponent("processed.mp4")
        let result = try await processor.export(input: input, output: output, settings: settings, includeAudio: true) { _ in }
        let before = try await summary(input), after = try await summary(output)
        try check(result.frames == 12 && after.times.count == before.times.count, "Every video frame must be exported")
        try check(zip(before.times, after.times).allSatisfy { abs($0.seconds - $1.seconds) < 0.0001 }, "VFR timestamps must be preserved")
        try check(abs(before.duration - after.duration) < 0.025, "Video duration changed")
        try check(after.audio == 1, "Source audio was lost")
        try check(try Data(contentsOf: input) == original, "Source video was modified")
        print("PASS offline export: 12/12 frames, VFR timestamps, duration, AAC audio, original unchanged; neural=\(settings.neuralEnabled)")

        // Portrait output must contain upright pixels, without another rotation tag.
        settings.neuralEnabled = false
        let rotatedOutput = directory.appendingPathComponent("portrait-processed.mp4")
        _ = try await processor.export(input: portrait, output: rotatedOutput, settings: settings, includeAudio: false) { _ in }
        let rotated = try await summary(rotatedOutput)
        try check(rotated.size == CGSize(width: 180, height: 320) && rotated.transform.isIdentity, "Portrait orientation was not baked correctly")
        try check(rotated.audio == 0 && rotated.times.count == 12, "Silent export lost frames or added audio")
        print("PASS portrait orientation and export without audio")

        do {
            _ = try VideoDestination(input: input, output: input)
            throw PortError.message("Source-overwrite protection failed")
        } catch let error as PortError {
            guard error.localizedDescription != "Source-overwrite protection failed" else { throw error }
        }
        let alias = directory.appendingPathComponent("input-hardlink.mp4")
        try FileManager.default.linkItem(at: input, to: alias)
        do {
            _ = try VideoDestination(input: input, output: alias)
            throw PortError.message("Hardlink protection failed")
        } catch let error as PortError {
            guard error.localizedDescription != "Hardlink protection failed" else { throw error }
        }
        print("PASS input and hardlink overwrite protection")

        let cancelled = directory.appendingPathComponent("cancelled.mp4")
        let sentinel = Data("existing output must survive cancellation".utf8)
        try sentinel.write(to: cancelled)
        let signal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let cancelledSettings = settings
        let task = Task {
            defer { signal.continuation.finish() }
            return try await processor.export(input: input, output: cancelled, settings: cancelledSettings, includeAudio: true) { _ in
                signal.continuation.yield(())
                // Hold after a real processed frame until the test requests cancellation.
                try? await Task.sleep(for: .seconds(5))
            }
        }
        var receivedFrame = false
        for await _ in signal.stream { receivedFrame = true; break }
        if !receivedFrame { _ = try await task.value; throw PortError.message("Cancellation test did not process a frame") }
        task.cancel()
        do { _ = try await task.value; throw PortError.message("Cancellation did not stop export") }
        catch { if !task.isCancelled { throw error } }
        try check(try Data(contentsOf: cancelled) == sentinel, "Cancellation replaced an existing output")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try check(!files.contains(where: { $0.hasPrefix(".dlss-export-") }), "Temporary export files were left behind")
        print("PASS cancellation cleans partial output and preserves existing destination")

        // A subsequent successful job can replace a previously existing output.
        _ = try await processor.export(input: input, output: cancelled, settings: settings, includeAudio: false) { _ in }
        try check(try await summary(cancelled).times.count == 12, "Export did not recover after cancellation")
        print("PASS export can restart after cancellation and replace its destination atomically")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw PortError.message(message) }
    }

    struct Summary {
        let times: [CMTime]
        let duration: Double
        let audio: Int
        let size: CGSize
        let transform: CGAffineTransform
    }
    static func summary(_ url: URL) async throws -> Summary {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw PortError.message("Test output has no video track") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        let provider = reader.outputProvider(for: output)
        guard reader.startReading() else { throw reader.error ?? PortError.message("Test decoder failed") }
        var times = [CMTime]()
        while let sample = try await provider.next() { times.append(sample.presentationTimeStamp) }
        if reader.status == .failed { throw reader.error ?? PortError.message("Test decoding failed") }
        return Summary(times: times, duration: try await asset.load(.duration).seconds,
            audio: try await asset.loadTracks(withMediaType: .audio).count,
            size: try await track.load(.naturalSize), transform: try await track.load(.preferredTransform))
    }

    static func makeFixture(_ url: URL, rotated: Bool) async throws {
        let surfaces = try MetalFrames()
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0) }
        let video = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
        let audio = writer.inputReceiver(for: audioInput)
        guard writer.startWriting() else { throw writer.error ?? PortError.message("Cannot write test clip") }
        writer.startSession(atSourceTime: .zero)
        // Alternating 30/60 ms intervals catch accidental constant-FPS re-timing.
        for i in 0..<12 {
            let time = Double(i / 2) * 0.09 + (i % 2 == 0 ? 0 : 0.03)
            let pixels = try Diagnostics.makePattern(surfaces, size: FrameSize(320, 180), phase: i * 3)
            try await video.append(CVReadOnlyPixelBuffer(unsafeBuffer: pixels), with: CMTime(seconds: time, preferredTimescale: 6000))
            let sample = try Diagnostics.makeAudio(at: Double(i) / 30)
            try await audio.append(CMReadySampleBuffer(unsafeBuffer: sample))
        }
        video.finish(); audio.finish()
        writer.endSession(atSourceTime: CMTime(seconds: 0.54, preferredTimescale: 6000))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PortError.message("Cannot finish test clip") }
    }
}
