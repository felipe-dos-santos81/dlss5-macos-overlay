import AppKit
import ScreenCaptureKit
import CoreMedia
import ScreenCore

struct CaptureSource: Identifiable {
    let id: String
    let title: String
    let display: SCDisplay?
    let window: SCWindow?
    var isWindow: Bool { window != nil }
    var frame: CGRect { window?.frame ?? display?.frame ?? .zero }
}

/// ScreenCaptureKit owns its output queue; the only cross-thread transfer is a
/// retained pixel buffer through a one-slot AsyncStream.
final class CaptureReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames = LatestFrames<CapturedFrame>()
    let onError: @Sendable (String) -> Void
    let onAudio: @Sendable (CMSampleBuffer) -> Void
    private let latestLock = NSLock()
    private var latest: CapturedFrame?
    init(onError: @escaping @Sendable (String) -> Void, onAudio: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onError = onError; self.onAudio = onAudio
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        frames.finish(); onError(error.localizedDescription)
    }
    func repeatLatest() {
        latestLock.lock(); defer { latestLock.unlock() }
        if let latest { frames.yield(latest) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        if outputType == .audio { onAudio(sampleBuffer); return }
        guard outputType == .screen,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
            let pixels = sampleBuffer.imageBuffer else { return }
        let frame = CapturedFrame(pixels: pixels, capturedAt: sampleBuffer.presentationTimeStamp.seconds)
        latestLock.lock(); latest = frame; frames.yield(frame); latestLock.unlock()
    }
}

@MainActor
final class ScreenCapture {
    private var stream: SCStream?
    private(set) var receiver: CaptureReceiver?
    private var configuration: SCStreamConfiguration?
    private var contentFilter: SCContentFilter?

    static func sources() async throws -> [CaptureSource] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays.enumerated().map { index, display in
            CaptureSource(id: "display:\(display.displayID)", title: "Display \(index + 1) · \(display.width)×\(display.height)", display: display, window: nil)
        }
        let windows = content.windows.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
            $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 70 &&
            !($0.title ?? "").isEmpty
        }.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            .map { window in
                CaptureSource(id: "window:\(window.windowID)", title: "\(window.owningApplication?.applicationName ?? "Window") — \(window.title ?? "")", display: nil, window: window)
            }
        return displays + windows
    }

    func start(source: CaptureSource, fps: Int, onError: @escaping @Sendable (String) -> Void,
               onAudio: @escaping @Sendable (CMSampleBuffer) -> Void) async throws -> CaptureReceiver {
        let filter: SCContentFilter
        if let window = source.window { filter = SCContentFilter(desktopIndependentWindow: window) }
        else if let display = source.display {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        } else { throw PortError.message("The source is no longer available.") }
        let config = SCStreamConfiguration()
        config.width = max(2, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()) / 2 * 2)
        config.height = max(2, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()) / 2 * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false // macOS keeps the real cursor responsive above the overlay.
        config.captureDynamicRange = .SDR
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000; config.channelCount = 2
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = true
        let receiver = CaptureReceiver(onError: onError, onAudio: onAudio)
        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "neuralscreen.capture", qos: .userInteractive))
        try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: DispatchQueue(label: "neuralscreen.audio", qos: .userInitiated))
        self.receiver = receiver; self.stream = stream; configuration = config; contentFilter = filter
        do { try await stream.startCapture() }
        catch { receiver.frames.finish(); self.receiver = nil; self.stream = nil; throw error }
        return receiver
    }

    func resize(to frame: CGRect) async throws {
        guard let configuration, let filter = contentFilter, let stream else { return }
        let w = max(2, Int(frame.width * CGFloat(filter.pointPixelScale)) / 2 * 2)
        let h = max(2, Int(frame.height * CGFloat(filter.pointPixelScale)) / 2 * 2)
        guard w != configuration.width || h != configuration.height else { return }
        configuration.width = w; configuration.height = h
        try await stream.updateConfiguration(configuration)
    }

    func stop() async {
        let old = stream; stream = nil
        receiver?.frames.finish(); receiver = nil
        try? await old?.stopCapture()
    }
}
