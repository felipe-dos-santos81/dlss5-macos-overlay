import AppKit
import Combine
import SwiftUI
import ScreenCore
import ScreenCaptureKit
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = RenderSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "renderSettings") }
            if running && oldValue != settings { capture.receiver?.repeatLatest() }
        }
    }
    @Published var mode: WorkspaceMode = .live
    let video: VideoJob
    @Published var sources = [CaptureSource]()
    @Published var sourceID = ""
    @Published var frame: RenderedFrame?
    @Published var running = false
    @Published var busy = false
    @Published var modelLoaded = false
    @Published private(set) var modelLoading = true
    @Published var status = "Loading NR.dlss…"
    @Published var error: String?
    @Published var overlayEnabled = false {
        didSet {
            if overlayEnabled && running && sourceVisible, let frame { overlay.update(frame: frame, bounds: activeBounds) }
            else { overlay.hide() }
        }
    }
    @Published var recording = false
    @Published var recordAudio = true
    @Published var fps = 0.0
    @Published var dropped = 0
    @Published var latency = 0.0
    private let capture = ScreenCapture()
    private let recorder = Recording()
    private let overlay = DesktopOverlay()
    private let engine: RenderEngine
    private var processingTask: Task<Void, Never>?
    private var geometryTask: Task<Void, Never>?
    private var activeSource: CaptureSource?
    private var activeBounds = CGRect.zero
    private var sourceVisible = true
    private var generation = 0
    private var lastPublish = 0.0
    private var count = 0
    private var recordingURL: URL?

    init() {
        let engine = try! RenderEngine()
        self.engine = engine
        video = VideoJob(engine: engine)
        if let data = UserDefaults.standard.data(forKey: "renderSettings"), var saved = try? JSONDecoder().decode(RenderSettings.self, from: data) {
            saved.sanitize(); settings = saved
        }
        recorder.onFailure = { [weak self] message in Task { @MainActor in
            self?.error = message
            if self?.recording == true { await self?.stopRecording() }
        } }
    }

    var selectedSource: CaptureSource? { sources.first { $0.id == sourceID } }

    func initialize(refreshCaptureSources: Bool = true) async {
        await loadDefaultModel()
        // Permission is requested only by the user's Refresh/Start action.
        if refreshCaptureSources && CGPreflightScreenCaptureAccess() { await refreshSources() }
    }

    func refreshSources() async {
        guard !busy, !running, !video.processing else { return }
        busy = true; defer { busy = false }
        // Refresh is a user action: explicitly request access before asking
        // replayd for content. A preflight check alone never shows consent.
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        do {
            sources = try await ScreenCapture.sources()
            if !sources.contains(where: { $0.id == sourceID }) { sourceID = sources.first?.id ?? "" }
            status = "Sources available: \(sources.count)."
        } catch {
            let failure = error as NSError
            if failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue {
                self.error = "macOS has not authorized screen capture for this build. Open macOS Permissions and enable DLSS 5, then fully quit and reopen the app. If the switch is already on, remove the old entry and add this app again."
            } else {
                self.error = "Could not retrieve sources: \(error.localizedDescription)"
            }
        }
    }

    private func loadDefaultModel() async {
        guard !running, !busy, !video.processing else { return }
        busy = true; modelLoading = true; status = "Loading NR.dlss…"
        defer { busy = false; modelLoading = false }
        do {
            try await engine.loadModel(BundledModel.url())
            modelLoaded = true
            status = "NR.dlss ready. Choose an image source."
        } catch {
            modelLoaded = false; self.error = error.localizedDescription
            status = "NR.dlss could not be loaded. Restart the complete application."
        }
    }

    func start() async {
        guard !running, !busy, !video.processing else { return }
        if settings.neuralEnabled && !modelLoaded { error = "NR.dlss is not ready. Wait for loading to finish or restart the application."; return }
        guard let source = selectedSource else { error = "Click Refresh Screens and Windows, then select a display or window."; return }
        busy = true; defer { busy = false }
        do {
            generation += 1; let token = generation
            await engine.invalidateHistory()
            let recorder = self.recorder
            let receiver = try await capture.start(source: source, fps: settings.captureFPS,
                onError: { [weak self] message in Task { @MainActor in
                    guard self?.generation == token else { return }
                    self?.error = message; await self?.stop()
                } }, onAudio: { sample in recorder.appendAudio(sample) })
            activeSource = source; activeBounds = source.frame; sourceVisible = true
            running = true; status = "Capture started. Compiling Metal kernels for the first neural frame…"
            lastPublish = ProcessInfo.processInfo.systemUptime; count = 0; fps = 0; frame = nil
            processingTask = Task { [weak self, engine] in
                for await captured in receiver.frames.stream {
                    guard !Task.isCancelled, let self, self.generation == token else { break }
                    let settings = self.settings
                    do {
                        let result = try await engine.process(captured, settings: settings)
                        guard !Task.isCancelled, self.generation == token, self.running else { break }
                        self.publish(result, receiver: receiver)
                    } catch {
                        guard !Task.isCancelled, self.generation == token else { break }
                        self.error = error.localizedDescription
                        Task { await self.stop() }
                        break
                    }
                }
            }
            if source.isWindow { followWindow(source, token: token) }
        } catch { self.error = error.localizedDescription; running = false }
    }

    private func publish(_ result: RenderedFrame, receiver: CaptureReceiver) {
        frame = result; dropped = receiver.frames.dropped
        let now = ProcessInfo.processInfo.systemUptime
        latency = max(0, (now - result.capturedAt) * 1000)
        count += 1
        if now - lastPublish > 1 { fps = Double(count) / (now - lastPublish); count = 0; lastPublish = now }
        status = result.neural ? "Metal · \(result.processingSize.width)×\(result.processingSize.height) → original resolution" : "Neural processing off · original image"
        if overlayEnabled && sourceVisible { overlay.update(frame: result, bounds: activeBounds) }
        if recording { recorder.append(result) }
    }

    private func followWindow(_ source: CaptureSource, token: Int) {
        guard let windowID = source.window?.windowID else { return }
        geometryTask = Task { [weak self] in
            var stableSize = source.frame.size
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.generation == token else { break }
                guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]])?.first,
                    let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                    let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else {
                    await self.stop(); self.status = "The source window was closed."; break
                }
                self.activeBounds = bounds
                self.sourceVisible = info[kCGWindowIsOnscreen as String] as? Bool != false
                if !self.sourceVisible { self.overlay.hide(); continue }
                if let frame = self.frame, self.overlayEnabled { self.overlay.update(frame: frame, bounds: bounds) }
                if stableSize == bounds.size {
                    do { try await self.capture.resize(to: bounds) }
                    catch { self.error = error.localizedDescription; await self.stop(); break }
                }
                stableSize = bounds.size
            }
        }
    }

    func stopAll() async {
        await stop()
        await video.cancelAndWait()
        video.player?.pause()
    }

    func stop() async {
        guard running || processingTask != nil else { return }
        busy = true; defer { busy = false }
        generation += 1; running = false
        let processing = processingTask
        processing?.cancel(); processingTask = nil
        geometryTask?.cancel(); geometryTask = nil
        overlay.hide(); overlayEnabled = false
        await capture.stop()
        await processing?.value
        if recording { await stopRecording() }
        status = "Stopped."
    }

    func toggleRecording() async {
        if recording { await stopRecording(); return }
        guard let frame, running else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "DLSS-\(Int(Date().timeIntervalSince1970)).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // NSSavePanel authorizes replacing a selected existing destination.
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try await recorder.start(url: url, width: CVPixelBufferGetWidth(frame.pixels), height: CVPixelBufferGetHeight(frame.pixels), withAudio: recordAudio)
            recordingURL = url; recording = true
        } catch { self.error = error.localizedDescription }
    }
    private func stopRecording() async {
        recording = false
        do { try await recorder.stop(); status = "Saved: \(recordingURL?.lastPathComponent ?? "video")" }
        catch { self.error = error.localizedDescription }
    }
    func screenshot() {
        guard let frame else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "DLSS.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ImageExport.writePNG(frame.pixels, to: url) } catch { self.error = error.localizedDescription }
    }
    func applyProfile() {
        settings.tone = settings.profile == "neutral" ? 0 : 1
        settings.structure = settings.profile == "neutral" ? 0 : 1
    }
}
