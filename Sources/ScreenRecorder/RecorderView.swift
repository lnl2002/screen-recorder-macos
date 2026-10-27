import SwiftUI
import ScreenCaptureKit
import RecorderCore

struct RecorderView: View {
    @ObservedObject var model: RecorderModel
    var body: some View {
        VStack(spacing: 18) {
            header
            if !model.permissionGranted { permissionCard }
            previewCard
            sourceControls
            motionControls
            actionBar
        }
        .padding(24).frame(width: 720)
        .task { await model.refreshDisplays(); model.updateCameraPreview() }
        .onChange(of: model.selectedDisplay) { model.refreshPreview() }
        .onChange(of: model.webcam.enabled) { model.updateCameraPreview() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill").font(.system(size: 30)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recorder").font(.title2.weight(.semibold))
                Text(model.tr("Record once. Find your focus.")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase == .recording, let start = model.startedAt {
                HStack(spacing: 7) { Circle().fill(.red).frame(width: 9, height: 9); Text(start, style: .timer).monospacedDigit().fontWeight(.medium) }
                    .padding(.horizontal, 12).padding(.vertical, 7).background(.red.opacity(0.1), in: Capsule())
            }
            Picker(model.tr("Language"), selection: $model.language) { ForEach(AppLanguage.allCases) { Text($0.name).tag($0) } }
                .labelsHidden().frame(width: 120)
        }
    }

    private var permissionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tr("Screen Recording permission")).fontWeight(.semibold)
                Text(model.tr("Allow access so this app can record your selected screen.")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.tr("Allow screen recording")) { Task { await model.refreshDisplays(requestPermission: true) } }.buttonStyle(.borderedProminent).tint(.orange)
            Button { model.openPrivacy() } label: { Image(systemName: "gear") }.help(model.tr("System Settings"))
        }.padding(14).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var previewCard: some View {
        PreviewCanvas(model: model).aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.12)))
            .overlay(alignment: .topLeading) {
                Label(model.phase == .recording ? model.tr("Recording") : model.tr("Live preview"), systemImage: model.phase == .recording ? "record.circle.fill" : "eye.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule()).padding(10)
            }
    }

    private var sourceControls: some View {
        VStack(spacing: 12) {
            HStack {
                Label(model.tr("Capture"), systemImage: "display").font(.headline); Spacer()
                Button { model.openSession() } label: { Image(systemName: "folder.badge.plus") }.buttonStyle(.borderless).help(model.tr("Open an existing recording session"))
                Button { Task { await model.refreshDisplays() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help(model.tr("Refresh screens"))
            }
            HStack(spacing: 12) {
                Picker(model.tr("Screen"), selection: $model.selectedDisplay) {
                    if model.displays.isEmpty { Text(model.tr("No screen selected")).tag(UInt32(0)) }
                    ForEach(model.displays, id: \.displayID) { display in
                        Text("\(display.displayID == CGMainDisplayID() ? model.tr("Main display") : "\(model.tr("Display")) \(display.displayID)") · \(display.width) × \(display.height)").tag(display.displayID)
                    }
                }.frame(maxWidth: .infinity)
                optionToggle("speaker.wave.2.fill", "System audio", isOn: $model.systemAudio)
                optionToggle("video.fill", "Webcam", isOn: $model.webcam.enabled)
            }
            if model.webcam.enabled {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
                    Text(model.tr("Webcam size")).font(.callout); Slider(value: $model.webcam.size, in: 0.12...0.40)
                    Text("\(Int(model.webcam.size * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
                }
                if let cameraError = model.preview.cameraError { Label(model.tr(cameraError), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            }
        }.padding(15).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12)).disabled(model.busy)
    }

    private var motionControls: some View {
        VStack(spacing: 12) {
            HStack {
                Label(model.tr("Camera style"), systemImage: "viewfinder").font(.headline); Spacer()
                Picker(model.tr("Export"), selection: $model.quality) { ForEach(ExportQuality.allCases) { Text(model.tr($0.title)).tag($0) } }
                    .labelsHidden().frame(width: 210)
            }
            Picker(model.tr("Camera style"), selection: $model.settings.mode) {
                ForEach(ZoomMode.allCases) { mode in Label(model.tr(mode.title), systemImage: modeIcon(mode)).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden()
            if model.settings.mode != .off {
                HStack(spacing: 12) {
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary); Text(model.tr("Zoom")).frame(width: 52, alignment: .leading)
                    Slider(value: $model.settings.zoom, in: 1.2...3); Text(String(format: "%.1f×", model.settings.zoom)).monospacedDigit().frame(width: 38)
                    Button { smoothPreset() } label: { Label(model.tr("Smooth preset"), systemImage: "wand.and.stars") }
                }
                DisclosureGroup(model.tr("Fine tune")) {
                    VStack(spacing: 9) {
                        setting(model.tr("Glide duration"), value: $model.settings.response, range: 0.15...1.2, label: String(format: "%.2f s", model.settings.response))
                        if model.settings.mode == .auto { setting(model.tr("Hold after click"), value: $model.settings.hold, range: 0.3...5, label: String(format: "%.1f s", model.settings.hold)) }
                        setting(model.tr("Quiet zone"), value: $model.settings.deadZone, range: 0...0.4, label: String(format: "%.0f%%", model.settings.deadZone * 100))
                    }.padding(.top, 8)
                }.font(.callout)
            }
        }.padding(15).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12)).disabled(model.busy)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if model.phase == .exporting { ProgressView(value: model.progress) }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tr(model.status)).font(.callout).foregroundStyle(.secondary)
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                }
                Spacer()
                if model.session != nil && !model.busy {
                    Button { model.reveal() } label: { Image(systemName: model.output == nil ? "folder" : "film") }.help(model.tr(model.output == nil ? "Session folder" : "Show MP4"))
                    Button { Task { await model.export() } } label: { Label(model.tr("Export again"), systemImage: "square.and.arrow.up") }
                }
                if model.phase == .recording {
                    Button { Task { await model.stop() } } label: { Label(model.tr("Stop & export"), systemImage: "stop.fill") }.buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                } else if model.phase == .exporting {
                    Button(model.tr("Cancel export")) { model.cancelExport() }.controlSize(.large)
                } else {
                    Button { Task { await model.start() } } label: { Label(model.tr("Record"), systemImage: "record.circle.fill") }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).disabled(!model.canRecord)
                }
            }
        }
    }

    private func optionToggle(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Label(model.tr(title), systemImage: icon) }.toggleStyle(.switch).fixedSize()
    }
    private func modeIcon(_ mode: ZoomMode) -> String { mode == .auto ? "scope" : mode == .follow ? "cursorarrow.motionlines" : "rectangle.inset.filled" }
    private func smoothPreset() { model.settings.response = 0.75; model.settings.hold = 2; model.settings.lead = 0.35; model.settings.deadZone = 0.12 }
    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack { Text(title).frame(width: 120, alignment: .leading); Slider(value: value, in: range); Text(label).monospacedDigit().foregroundStyle(.secondary).frame(width: 58) }
    }
}

private struct PreviewCanvas: View {
    @ObservedObject var model: RecorderModel
    @ObservedObject private var preview: PreviewManager
    init(model: RecorderModel) { self.model = model; preview = model.preview }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image = preview.screenImage { Image(nsImage: image).resizable().scaledToFit() }
                else { VStack(spacing: 10) { Image(systemName: "display").font(.system(size: 44)); Text(model.tr("Waiting for screen preview…")) }.foregroundStyle(.white.opacity(0.55)) }
                if model.phase == .idle, model.webcam.enabled, preview.cameraReady {
                    CameraPreviewRepresentable(session: preview.cameraSession).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 8)
                        .frame(width: diameter(proxy.size), height: diameter(proxy.size)).position(x: model.webcam.x * proxy.size.width, y: model.webcam.y * proxy.size.height)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let radius = diameter(proxy.size) / 2
                            model.webcam.x = min(1 - radius / proxy.size.width, max(radius / proxy.size.width, value.location.x / proxy.size.width))
                            model.webcam.y = min(1 - radius / proxy.size.height, max(radius / proxy.size.height, value.location.y / proxy.size.height))
                        })
                }
            }
        }
    }
    private func diameter(_ size: CGSize) -> CGFloat { CGFloat(model.webcam.size) * min(size.width, size.height) }
}
