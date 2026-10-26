import SwiftUI
import ScreenCaptureKit
import RecorderCore

struct RecorderView: View {
    @ObservedObject var model: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Screen Recorder").font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text("Record once. Find your focus.").foregroundStyle(.secondary)
                }
                Spacer()
                if model.phase == .recording, let start = model.startedAt {
                    HStack { Circle().fill(.red).frame(width: 8, height: 8); Text(start, style: .timer).monospacedDigit() }
                        .padding(10).background(.red.opacity(0.10), in: Capsule())
                } else {
                    Image(systemName: "viewfinder").font(.system(size: 30, weight: .light)).foregroundStyle(.orange)
                }
            }

            if !model.permissionGranted {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Screen Recording permission", systemImage: "lock.shield").font(.headline)
                        Text("Allow access so this app can record your selected screen.").foregroundStyle(.secondary)
                        HStack {
                            Button("Allow screen recording") { Task { await model.refreshDisplays(requestPermission: true) } }
                            Button("System Settings") { model.openPrivacy() }
                            Button("Refresh") { Task { await model.refreshDisplays() } }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Capture").font(.headline)
                        Spacer()
                        Button { Task { await model.refreshDisplays() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Refresh screens").disabled(model.busy || model.isLoadingDisplays)
                    }
                    Picker("Screen", selection: $model.selectedDisplay) {
                        if model.displays.isEmpty { Text("No screen selected").tag(UInt32(0)) }
                        ForEach(model.displays, id: \.displayID) { display in
                            Text("\(display.displayID == CGMainDisplayID() ? "Main display" : "Display \(display.displayID)") · \(display.width) × \(display.height)")
                                .tag(display.displayID)
                        }
                    }
                    Toggle("Record system audio", isOn: $model.systemAudio)
                    Picker("Export", selection: $model.quality) {
                        ForEach(ExportQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Text("The recorder controls are excluded. Original pixels are retained up to 4K. MP4 export renders every frame at 60 fps.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).disabled(model.busy)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("Camera style").font(.headline)
                        Spacer()
                        Button("Smooth preset") {
                            model.settings.response = 0.75
                            model.settings.hold = 2
                            model.settings.lead = 0.35
                            model.settings.deadZone = 0.12
                        }.buttonStyle(.borderless)
                    }
                    Picker("Camera style", selection: $model.settings.mode) {
                        ForEach(ZoomMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(modeDescription).font(.callout).foregroundStyle(.secondary).frame(height: 34, alignment: .topLeading)
                    if model.settings.mode != .off {
                        setting("Zoom", value: $model.settings.zoom, range: 1.2...3, label: String(format: "%.1f×", model.settings.zoom))
                        Text(detailHint).font(.caption).foregroundStyle(.secondary)
                        setting("Glide duration", value: $model.settings.response, range: 0.15...1.2, label: String(format: "%.2f s", model.settings.response))
                        if model.settings.mode == .auto {
                            setting("Hold after click", value: $model.settings.hold, range: 0.3...5, label: String(format: "%.1f s", model.settings.hold))
                        }
                        DisclosureGroup("Fine tune") {
                            VStack(spacing: 10) {
                                setting("Quiet zone", value: $model.settings.deadZone, range: 0...0.4,
                                        label: String(format: "%.0f%%", model.settings.deadZone * 100))
                                if model.settings.mode == .auto {
                                    setting("Lead-in", value: $model.settings.lead, range: 0...1,
                                            label: String(format: "%.2f s", model.settings.lead))
                                }
                            }.padding(.top, 8)
                        }
                    }
                }.padding(8).disabled(model.busy)
            }

            VStack(alignment: .leading, spacing: 9) {
                if model.phase == .exporting { ProgressView(value: model.progress) }
                Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = model.error {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    if model.phase == .recording {
                        Button { Task { await model.stop() } } label: { Label("Stop & export", systemImage: "stop.fill") }
                            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                            .keyboardShortcut("r", modifiers: [.command, .shift])
                    } else if model.phase == .exporting {
                        Button("Cancel export") { model.cancelExport() }.controlSize(.large)
                    } else {
                        Button { Task { await model.start() } } label: { Label("Record", systemImage: "record.circle") }
                            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(!model.canRecord)
                            .keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                    if model.session != nil && !model.busy {
                        Button("Export again") { Task { await model.export() } }
                        Button(model.output == nil ? "Session folder" : "Show MP4") { model.reveal() }
                    }
                    Spacer()
                    Button { model.openSession() } label: { Image(systemName: "folder") }
                        .help("Open an existing recording session").disabled(model.busy)
                }.padding(.top, 4)
            }
            Text("Originals are saved in Movies / Screen Recorder.").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28).frame(width: 560)
        .task { await model.refreshDisplays() }
    }

    private var modeDescription: String {
        switch model.settings.mode {
        case .auto: return "Zoom around clicks, follow the action, then ease back to the full screen."
        case .follow: return "Stay zoomed in. The camera gently follows your mouse across the screen."
        case .off: return "Keep the full screen in view, with no camera movement."
        }
    }

    private var detailHint: String {
        if let session = model.session {
            let width = Int(Double(session.manifest.width) / model.settings.zoom)
            let height = Int(Double(session.manifest.height) / model.settings.zoom)
            return "This source has about \(width) × \(height) pixels of detail at this zoom. More export pixels cannot recover missing detail."
        }
        return "For crisp zoomed text, record a high-resolution display or use a lower zoom. A 1080p source at 2× contains only 960 × 540 pixels in view."
    }

    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 108, alignment: .leading)
            Slider(value: value, in: range)
            Text(label).monospacedDigit().foregroundStyle(.secondary).frame(width: 57, alignment: .trailing)
        }
    }
}
