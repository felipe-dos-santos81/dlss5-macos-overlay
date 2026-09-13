import SwiftUI
import AppKit

enum WorkspaceMode: String { case live, video }

struct ControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var video: VideoJob
    init(model: AppModel) { self.model = model; self.video = model.video }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Workspace", selection: $model.mode) {
                    Label("Realtime", systemImage: "display").tag(WorkspaceMode.live)
                    Label("Upload Video", systemImage: "film").tag(WorkspaceMode.video)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
                    .disabled(model.running || model.busy || video.processing || video.inspecting)
                Spacer()
                Text(model.mode == .live ? "Real-time screen processing" : "Process and export an existing video")
                    .font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 16)
                Label(model.modelLoaded ? "NR.dlss · Ready" : model.modelLoading ? "NR.dlss · Loading…" : "NR.dlss · Unavailable",
                      systemImage: model.modelLoaded ? "checkmark.circle.fill" : model.modelLoading ? "hourglass" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(model.modelLoaded ? Color.mint : Color.secondary)
                    .help("NR.dlss is built in and used automatically in both workspaces.")
            }.padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            if model.mode == .live { LiveControlsView(model: model) }
            else { VideoView(model: model, video: video) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "en"))
        .onChange(of: model.mode) { _, _ in video.player?.pause() }
        .alert("DLSS 5", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            Button("macOS Permissions") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        } message: { Text(model.error ?? "") }
    }
}

struct LiveControlsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
              ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DLSS 5").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("APPLE SILICON").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.mint)
                    }
                    GroupBox("Source") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $model.sourceID) {
                                if model.sources.isEmpty { Text("Refresh to select a source").tag("") }
                                ForEach(model.sources) { source in Text(source.title).tag(source.id) }
                            }.labelsHidden().disabled(model.running || model.busy)
                            Button("Refresh Screens and Windows") { Task { await model.refreshSources() } }.disabled(model.running || model.busy)
                            Picker("Capture", selection: $model.settings.captureFPS) {
                                ForEach([15, 30, 60], id: \.self) { Text("\($0) FPS").tag($0) }
                            }.disabled(model.running)
                        }.padding(4)
                    }
                    ProcessingSettingsView(settings: $model.settings)
                }.padding(22)
              }
              Divider()
              VStack(alignment: .leading, spacing: 12) {
                    Toggle("Overlay On / Off", isOn: $model.overlayEnabled).disabled(!model.running)
                        .help("Show the processed image over the game. Turn off to keep only the panel preview.")
                    Text("Clicks pass through the overlay. ⌥⌘0 stops processing. ⌥⌘1 toggles the overlay.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.running ? "Stop" : "Start", systemImage: model.running ? "stop.fill" : "play.fill") {
                            Task { if model.running { await model.stop() } else { await model.start() } }
                        }.buttonStyle(.borderedProminent).tint(.mint).disabled(model.busy || model.modelLoading)
                        if model.busy { ProgressView().controlSize(.small) }
                    }
              }.padding(18)
            }.frame(width: 320)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 25) {
                    metric("PROCESSING", value: String(format: "%.1f FPS", model.fps))
                    metric("FRAME", value: String(format: "%.0f ms", model.frame?.milliseconds ?? 0))
                    metric("LATENCY", value: String(format: "%.0f ms", model.latency))
                    Spacer()
                    Circle().fill(model.running ? Color.mint : Color.gray).frame(width: 8, height: 8)
                }.padding(22)
                ZStack {
                    MetalPreview(frame: model.frame)
                    if model.frame == nil {
                        VStack(spacing: 14) {
                            Image(systemName: "display").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.mint)
                            Text(model.running ? "Preparing the first frame…" : "Desktop Preview").font(.title3)
                            Text("Select a source and click Start.").foregroundStyle(.secondary)
                        }.padding()
                    }
                }.frame(minWidth: 560, minHeight: 380)
                HStack {
                    Button("Screenshot", systemImage: "camera") { model.screenshot() }.disabled(model.frame == nil)
                    Button(model.recording ? "Stop Recording" : "Record Video", systemImage: model.recording ? "stop.circle.fill" : "record.circle") {
                        Task { await model.toggleRecording() }
                    }.tint(model.recording ? .red : .accentColor).disabled(!model.running || model.frame == nil)
                    Toggle("System Audio", isOn: $model.recordAudio).disabled(model.recording)
                    Spacer()
                }.padding(18)
                Divider()
                HStack {
                    Text(model.status).lineLimit(2)
                    Spacer()
                    Text("Dropped: \(model.dropped)").monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary).padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "en"))

    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .medium, design: .monospaced))
        }
    }
}
