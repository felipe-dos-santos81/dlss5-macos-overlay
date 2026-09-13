import SwiftUI
import AVKit
import ScreenCore

struct VideoView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var video: VideoJob

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("DLSS 5").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("APPLE SILICON").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.mint)
                        }
                        GroupBox("Video File") {
                            VStack(alignment: .leading, spacing: 10) {
                                if let info = video.info {
                                    Text(info.url.lastPathComponent).font(.headline).lineLimit(2).help(info.url.path)
                                    Text("\(info.size.width) × \(info.size.height) · \(VideoJob.time(info.duration))")
                                    Text(String(format: "%.3g FPS · %@", info.frameRate, info.hasAudio ? "Audio available" : "No audio track"))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else { Text("No video selected").foregroundStyle(.secondary) }
                                Button("Choose Video…", systemImage: "film") { Task { await video.chooseInput() } }
                                    .disabled(video.processing || video.inspecting)
                                if video.inspecting { ProgressView().controlSize(.small) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                        }
                        ProcessingSettingsView(settings: $video.settings).disabled(video.processing)
                        Text("Before / After is included in the export. Set it to 0.00 for the full processed image.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(22)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Keep Original Audio", isOn: $video.keepAudio)
                        .disabled(video.processing || video.info?.hasAudio != true)
                    Text("MP4 / H.264 · Original size and timing\nAudio is exported as stereo AAC.")
                        .font(.caption).foregroundStyle(.secondary)
                    if video.processing {
                        Button("Cancel Export", systemImage: "stop.fill") { Task { await video.cancelAndWait() } }
                    } else {
                        Button("Export Video…", systemImage: "square.and.arrow.up") { video.start(modelLoaded: model.modelLoaded) }
                            .buttonStyle(.borderedProminent).tint(.mint)
                            .disabled(video.info == nil || video.inspecting || model.busy || model.modelLoading || model.running)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }.frame(width: 320)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 25) {
                    metric("PROGRESS", String(format: "%.1f%%", video.progress * 100))
                    metric("FRAMES", "\(video.frameCount)")
                    metric("PROCESSING", String(format: "%.1f FPS", video.processingFPS))
                    metric("REMAINING", video.processing ? video.remaining.map(VideoJob.time) ?? "Estimating…" : "—")
                    Spacer()
                }.padding(22)
                ZStack {
                    Color.black
                    if video.processing, let frame = video.frame {
                        MetalPreview(frame: frame)
                    } else if !video.processing, let player = video.player {
                        VideoPlayer(player: player)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "film.stack").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.mint)
                            Text(video.processing ? "Preparing the first frame…" : "Process an Existing Video").font(.title3)
                            Text(video.processing ? "The first frame may take a few seconds." : "Choose a clip, adjust the effect, then export.").foregroundStyle(.secondary)
                        }.padding()
                    }
                }.frame(minWidth: 560, minHeight: 380)
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: video.progress).tint(.mint)
                    HStack {
                        if video.result != nil {
                            Picker("Preview", selection: Binding(get: { video.showingResult }, set: { video.selectPreview(result: $0) })) {
                                Text("Original").tag(false); Text("Result").tag(true)
                            }.pickerStyle(.segmented).frame(width: 200).disabled(video.processing)
                            Button("Show in Finder", systemImage: "folder") { video.revealResult() }
                        } else { Text("All frames · No screen capture required").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text("Elapsed \(VideoJob.time(video.elapsed))").font(.caption).monospacedDigit()
                    }
                }.padding(18)
                Divider()
                Text(video.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
        }
        .alert("Video Export", isPresented: Binding(get: { video.error != nil }, set: { if !$0 { video.error = nil } })) {
            Button("OK") { video.error = nil }
        } message: { Text(video.error ?? "") }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .medium, design: .monospaced))
        }
    }
}

struct ProcessingSettingsView: View {
    @Binding var settings: RenderSettings
    var body: some View {
        GroupBox("Neural Processing") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enabled", isOn: $settings.neuralEnabled)
                Picker("Profile", selection: $settings.profile) {
                    Text("Natural").tag("natural"); Text("Standard").tag("standard")
                    Text("Cinematic").tag("cinematic"); Text("Neutral").tag("neutral")
                }.onChange(of: settings.profile) { _, profile in
                    settings.tone = profile == "neutral" ? 0 : 1
                    settings.structure = profile == "neutral" ? 0 : 1
                }
                Picker("Processing Size", selection: $settings.processingLongEdge) {
                    ForEach([320, 384, 512, 640, 768, 960, 1280, 1920], id: \.self) { Text("\($0) px").tag($0) }
                }
                Text("Processing frame’s longest edge. Output keeps the original resolution.").font(.caption).foregroundStyle(.secondary)
                control("Intensity", $settings.intensity, 0...2)
                control("Local Tone", $settings.tone, 0...2)
                control("Structure", $settings.structure, 0...2)
                Toggle("Motion Awareness", isOn: $settings.temporal)
                control("Before / After", $settings.split, 0...1)
            }.padding(4)
        }
    }
    private func control(_ label: String, _ value: Binding<Float>, _ range: ClosedRange<Float>) -> some View {
        VStack(spacing: 4) {
            HStack { Text(label); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}
