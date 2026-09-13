import AVFoundation
import CoreVideo
import Foundation

/// All AVAssetWriter operations are confined to this serial queue. Each stream
/// has bounded pending work; an encoder stall cannot stall screen processing.
final class Recording: @unchecked Sendable {
    private let queue = DispatchQueue(label: "neuralscreen.recording", qos: .utility)
    private let lock = NSLock()
    private var pendingVideo = 0
    private var pendingAudio = 0
    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var lastVideo: CMTime?
    private var size: CGSize?
    private var failure: Error?
    var onFailure: (@Sendable (String) -> Void)?

    func start(url: URL, width: Int, height: Int, withAudio: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard self.writer == nil else { throw PortError.message("Recording is already in progress.") }
                    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(4_000_000, width * height * 8),
                                                          AVVideoAllowFrameReorderingKey: false]
                    ])
                    video.expectsMediaDataInRealTime = true
                    guard writer.canAdd(video) else { throw PortError.message("The H.264 encoder does not support this resolution.") }
                    writer.add(video)
                    self.adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,
                        sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    self.audio = nil
                    if withAudio {
                        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
                        audio.expectsMediaDataInRealTime = true
                        if writer.canAdd(audio) { writer.add(audio); self.audio = audio }
                    }
                    guard writer.startWriting() else { throw writer.error ?? PortError.message("Could not start recording.") }
                    self.writer = writer; self.video = video; self.startTime = nil; self.lastVideo = nil
                    self.size = CGSize(width: width, height: height); self.failure = nil
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func append(_ frame: RenderedFrame) {
        lock.lock()
        guard pendingVideo < 3 else { lock.unlock(); return }
        pendingVideo += 1; lock.unlock()
        queue.async {
            defer { self.lock.lock(); self.pendingVideo -= 1; self.lock.unlock() }
            guard let writer = self.writer, let video = self.video, self.failure == nil else { return }
            guard self.size == CGSize(width: CVPixelBufferGetWidth(frame.pixels), height: CVPixelBufferGetHeight(frame.pixels)) else {
                self.fail(PortError.message("The source size changed. Recording stopped; start a new file.")); return
            }
            let pts = CMTime(seconds: frame.capturedAt, preferredTimescale: 600000)
            guard self.lastVideo.map({ pts > $0 }) ?? true else { return }
            if self.startTime == nil { writer.startSession(atSourceTime: pts); self.startTime = pts }
            guard video.isReadyForMoreMediaData else { return }
            if self.adaptor?.append(frame.pixels, withPresentationTime: pts) == true { self.lastVideo = pts }
            else { self.fail(writer.error ?? PortError.message("Could not write the video frame.")) }
        }
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        lock.lock()
        guard pendingAudio < 12 else { lock.unlock(); return }
        pendingAudio += 1; lock.unlock()
        queue.async {
            defer { self.lock.lock(); self.pendingAudio -= 1; self.lock.unlock() }
            guard let writer = self.writer, let start = self.startTime,
                sample.presentationTimeStamp >= start, let audio = self.audio,
                audio.isReadyForMoreMediaData, self.failure == nil else { return }
            if !audio.append(sample) { self.fail(writer.error ?? PortError.message("Could not write the audio sample.")) }
        }
    }

    private func fail(_ error: Error) { failure = error; onFailure?(error.localizedDescription) }

    func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let writer = self.writer else { continuation.resume(); return }
                let failure = self.failure
                self.writer = nil; self.adaptor = nil
                if self.startTime == nil {
                    writer.cancelWriting()
                    continuation.resume(throwing: PortError.message("The recording did not receive any video frames.")); return
                }
                self.video?.markAsFinished(); self.audio?.markAsFinished()
                writer.finishWriting {
                    if let error = writer.error ?? failure { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }
}
