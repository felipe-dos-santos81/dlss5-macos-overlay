import AppKit
import AVFoundation
import Combine
import ScreenCore
import UniformTypeIdentifiers

@MainActor
final class VideoJob: ObservableObject {
    @Published var info: VideoInfo?
    @Published var settings = RenderSettings()
    @Published var keepAudio = true
    @Published var inspecting = false
    @Published var processing = false
    @Published var progress = 0.0
    @Published var frameCount = 0
    @Published var elapsed = 0.0
    @Published var frame: RenderedFrame?
    @Published var result: VideoExportResult?
    @Published var player: AVPlayer?
    @Published var showingResult = false
    @Published var status = "Choose a video to process every frame and export a new MP4."
    @Published var error: String?
    private let processor: VideoProcessor
    private var task: Task<Void, Never>?

    init(engine: RenderEngine) { processor = VideoProcessor(engine: engine) }

    var processingFPS: Double { elapsed > 0 ? Double(frameCount) / elapsed : 0 }
    var remaining: Double? { progress > 0.01 && progress < 1 ? elapsed * (1 - progress) / progress : nil }

    func chooseInput() async {
        guard !processing, !inspecting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose an SDR video supported by macOS, such as MP4 or MOV."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspecting = true; defer { inspecting = false }
        do {
            let next = try await VideoInfo.inspect(url)
            player?.pause()
            info = next; result = nil; frame = nil; frameCount = 0; progress = 0
            elapsed = 0; showingResult = false; player = AVPlayer(url: url)
            status = "Ready. Export processes all frames at their original timing."
        } catch { self.error = error.localizedDescription }
    }

    func start(modelLoaded: Bool) {
        guard !processing, !inspecting, let info else { return }
        if settings.neuralEnabled && !modelLoaded { error = "NR.dlss is not ready. Wait for loading to finish or restart the application."; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = info.url.deletingPathExtension().lastPathComponent + "-DLSS5.mp4"
        panel.message = "Save the processed video as a new MP4. Your source video stays unchanged."
        guard panel.runModal() == .OK, let output = panel.url else { return }
        do { _ = try VideoDestination(input: info.url, output: output) }
        catch { self.error = error.localizedDescription; return }
        var snapshot = settings; snapshot.sanitize()
        let audio = keepAudio
        player?.pause(); player = AVPlayer(url: info.url); showingResult = false
        frame = nil; result = nil; progress = 0; frameCount = 0; elapsed = 0
        processing = true; status = "Preparing export. The first frame may take a few seconds…"
        task = Task { [self, processor] in
            defer { processing = false; task = nil }
            do {
                let exported = try await processor.export(input: info.url, output: output,
                    settings: snapshot, includeAudio: audio) { [weak self] update in
                        await self?.receive(update)
                    }
                result = exported; frameCount = exported.frames; progress = 1
                status = "Saved \(exported.frames) frames to \(output.lastPathComponent)."
                showingResult = true; player = AVPlayer(url: output)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    status = "Export cancelled. The source and any previous output are unchanged."
                } else { self.error = error.localizedDescription; status = "Export failed. The source video is unchanged." }
            }
        }
    }

    func cancelAndWait() async {
        guard let task else { return }
        status = "Cancelling after the current GPU operation…"
        task.cancel(); await task.value
    }

    private func receive(_ update: VideoProgress) {
        frame = update.frame; frameCount = update.count
        progress = update.fraction; elapsed = update.elapsed
        status = update.fraction >= 0.99 ? "Finishing video and audio…" : "Processing every frame…"
    }

    func selectPreview(result showResult: Bool) {
        guard !processing, let url = showResult ? result?.url : info?.url else { return }
        player?.pause(); showingResult = showResult; player = AVPlayer(url: url)
    }

    func revealResult() { if let url = result?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(min(seconds, 359999))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
}
