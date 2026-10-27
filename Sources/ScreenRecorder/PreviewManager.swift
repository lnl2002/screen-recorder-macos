import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

@MainActor
final class PreviewManager: ObservableObject {
    @Published var screenImage: NSImage?
    @Published var cameraReady = false
    @Published var cameraError: String?
    let cameraSession = AVCaptureSession()
    private var screenTask: Task<Void, Never>?
    private var configuredCamera = false

    func startScreen(display: SCDisplay) {
        screenTask?.cancel()
        screenTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                    let config = SCStreamConfiguration()
                    let aspect = max(0.1, filter.contentRect.width / filter.contentRect.height)
                    config.width = 1280; config.height = Int(1280 / aspect)
                    config.showsCursor = true
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard !Task.isCancelled else { return }
                    self?.screenImage = NSImage(cgImage: image, size: .zero)
                } catch { }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopScreen() {
        screenTask?.cancel(); screenTask = nil
    }

    func setCameraEnabled(_ enabled: Bool) async {
        if !enabled { await stopCamera(); cameraError = nil; return }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed else { cameraError = "Camera permission is required for webcam preview."; return }
        do {
            if !configuredCamera {
                guard let device = AVCaptureDevice.default(for: .video) else { throw RecorderError.message("No camera is available.") }
                let input = try AVCaptureDeviceInput(device: device)
                guard cameraSession.canAddInput(input) else { throw RecorderError.message("The camera could not be configured.") }
                cameraSession.addInput(input); configuredCamera = true
            }
            let session = cameraSession
            await Task.detached { if !session.isRunning { session.startRunning() } }.value
            cameraReady = true; cameraError = nil
        } catch { cameraError = error.localizedDescription; cameraReady = false }
    }

    func stopCamera() async {
        let session = cameraSession
        await Task.detached { if session.isRunning { session.stopRunning() } }.value
        cameraReady = false
    }

    func stopAll() async { stopScreen(); await stopCamera() }
}

struct CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraLayerView { CameraLayerView(session: session) }
    func updateNSView(_ nsView: CameraLayerView, context: Context) { }
}

final class CameraLayerView: NSView {
    private let preview: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true; layer = CALayer()
        preview.videoGravity = .resizeAspectFill
        preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); preview.frame = bounds }
}

