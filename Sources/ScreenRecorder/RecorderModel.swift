import AppKit
import SwiftUI
import ScreenCaptureKit
import RecorderCore

@MainActor
final class RecorderModel: ObservableObject {
    enum Phase: String { case idle, preparing, recording, stopping, exporting }
    @Published var phase = Phase.idle
    @Published var language: AppLanguage = .en {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }
    @Published var displays: [SCDisplay] = []
    @Published var selectedDisplay: UInt32 = 0
    @Published var settings = CameraSettings() {
        didSet { if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "cameraSettings") } }
    }
    @Published var systemAudio = false
    @Published var webcam = WebcamSettings() {
        didSet { if let data = try? JSONEncoder().encode(webcam) { UserDefaults.standard.set(data, forKey: "webcamSettings") } }
    }
    @Published var quality: ExportQuality = .source {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "exportQuality") }
    }
    @Published var error: String?
    @Published var status = "Choose a screen and a camera style."
    @Published var output: URL?
    @Published var session: RecordingSession?
    @Published var progress = 0.0
    @Published var startedAt: Date?
    @Published var isLoadingDisplays = false
    @Published var permissionGranted = CGPreflightScreenCaptureAccess()
    private let capture = CaptureEngine()
    private let exporter = VideoExporter()
    let preview = PreviewManager()
    private var progressTask: Task<Void, Never>?
    private var recordingDirectory: URL?
    var busy: Bool { phase != .idle }
    var canRecord: Bool { !busy && !displays.isEmpty && !isLoadingDisplays }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "appLanguage"), let saved = AppLanguage(rawValue: raw) { language = saved }
        if let saved = UserDefaults.standard.string(forKey: "exportQuality"), let quality = ExportQuality(rawValue: saved) {
            self.quality = quality
        }
        if let data = UserDefaults.standard.data(forKey: "cameraSettings"),
           let saved = try? JSONDecoder().decode(CameraSettings.self, from: data) { settings = saved.sanitized }
        if let data = UserDefaults.standard.data(forKey: "webcamSettings"),
           let saved = try? JSONDecoder().decode(WebcamSettings.self, from: data) { webcam = saved.sanitized }
        capture.onFailure = { [weak self] error in
            guard let self else { return }
            self.error = error.localizedDescription
            if self.phase == .recording { Task { await self.stop() } }
        }
    }

    func tr(_ english: String) -> String { L10n.text(english, language) }

    func refreshDisplays(requestPermission: Bool = false) async {
        guard !busy, !isLoadingDisplays else { return }
        permissionGranted = CGPreflightScreenCaptureAccess()
        if !permissionGranted {
            if requestPermission { _ = CGRequestScreenCaptureAccess() }
            permissionGranted = CGPreflightScreenCaptureAccess()
            guard permissionGranted else {
                status = "Allow Screen Recording in System Settings, then refresh screens. You may need to reopen the app."
                return
            }
        }
        isLoadingDisplays = true
        defer { isLoadingDisplays = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays.sorted { $0.displayID < $1.displayID }
            if !displays.contains(where: { $0.displayID == selectedDisplay }) {
                selectedDisplay = displays.first(where: { $0.displayID == CGMainDisplayID() })?.displayID ?? displays.first?.displayID ?? 0
            }
            status = displays.isEmpty ? "No screens available." : "Ready to record. Your original video stays saved."
            refreshPreview()
        } catch { self.error = error.localizedDescription }
    }

    func start() async {
        guard canRecord, let display = displays.first(where: { $0.displayID == selectedDisplay }) else { return }
        phase = .preparing; error = nil; output = nil
        status = "Get ready…"
        do {
            await preview.stopAll()
            await CountdownPanel(displayID: display.displayID).run()
            status = "Starting screen capture…"
            recordingDirectory = try await capture.start(display: display, systemAudio: systemAudio, webcam: webcam.sanitized)
            startedAt = Date(); phase = .recording
            status = webcam.enabled
                ? "Recording. Drag the camera bubble to move it, or resize it from an edge."
                : "Recording. Stop from this window or the menu bar."
        } catch {
            phase = .idle; self.error = error.localizedDescription; status = "Could not start recording."
            resumePreview()
        }
    }

    func stop() async {
        guard phase == .recording else { return }
        phase = .stopping; status = "Saving the original recording…"
        do {
            let saved = try await capture.stop(settings: settings.sanitized)
            session = saved; startedAt = nil
            phase = .idle
            resumePreview()
            await export()
        } catch {
            phase = .idle; startedAt = nil
            self.error = "\(error.localizedDescription)\nSession files: \(recordingDirectory?.path ?? RecordingSession.root.path)"
            status = "Recording stopped with an error."
            resumePreview()
        }
    }

    func refreshPreview() {
        guard phase == .idle, let display = displays.first(where: { $0.displayID == selectedDisplay }) else { return }
        preview.startScreen(display: display)
    }

    func updateCameraPreview() {
        guard phase == .idle else { return }
        Task { await preview.setCameraEnabled(webcam.enabled) }
    }

    private func resumePreview() {
        refreshPreview()
        Task { await preview.setCameraEnabled(webcam.enabled) }
    }

    func export() async {
        guard phase == .idle, let session else { return }
        phase = .exporting; progress = 0; error = nil; status = "Rendering camera movement and exporting MP4…"
        let snapshot = settings.sanitized
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.progress = self?.exporter.progress ?? 0
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { progressTask?.cancel(); progressTask = nil; phase = .idle }
        do {
            output = try await exporter.export(session, settings: snapshot, quality: quality)
            progress = 1; status = "MP4 ready. Change the camera style to export another version."
        } catch is CancellationError {
            status = "Export cancelled. Your original recording is safe."
        } catch {
            self.error = error.localizedDescription
            status = "Export failed. Your original recording is safe; you can retry."
        }
    }

    func cancelExport() { exporter.cancel(); status = "Cancelling export… Your original recording is safe." }
    func openSession() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.directoryURL = RecordingSession.root
        panel.message = tr("Choose a recording folder containing manifest.json and screen.mov.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let saved = try RecordingSession.open(url)
            session = saved; settings = saved.manifest.settings.sanitized; output = nil; error = nil
            if let savedWebcam = saved.manifest.webcam { webcam = savedWebcam.sanitized }
            status = "Session opened. Choose a camera style and export."
        } catch { self.error = error.localizedDescription }
    }

    func reveal() {
        if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
        else if let session { NSWorkspace.shared.open(session.directory) }
    }
    func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
