import AppKit
import AVFoundation
import RecorderCore

@MainActor
final class FloatingCameraPanel: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let displayFrame: CGRect

    init(session: AVCaptureSession, displayID: CGDirectDisplayID, settings: WebcamSettings) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main!
        displayFrame = screen.frame
        let value = settings.sanitized
        let diameter = max(120, value.size * min(screen.frame.width, screen.frame.height))
        let frame = CGRect(x: screen.frame.minX + value.x * screen.frame.width - diameter / 2,
                           y: screen.frame.maxY - value.y * screen.frame.height - diameter / 2,
                           width: diameter, height: diameter)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 120, height: 120)
        panel.maxSize = NSSize(width: min(screen.frame.width, screen.frame.height) * 0.5,
                               height: min(screen.frame.width, screen.frame.height) * 0.5)
        panel.aspectRatio = NSSize(width: 1, height: 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let preview = CameraPreviewView(frame: CGRect(origin: .zero, size: frame.size), session: session)
        panel.contentView = preview
        panel.orderFrontRegardless()
    }

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    var settings: WebcamSettings {
        let frame = panel.frame
        var value = WebcamSettings()
        value.enabled = true
        value.size = frame.width / min(displayFrame.width, displayFrame.height)
        value.x = (frame.midX - displayFrame.minX) / displayFrame.width
        value.y = (displayFrame.maxY - frame.midY) / displayFrame.height
        return value.sanitized
    }

    func close() { panel.orderOut(nil); panel.close() }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let side = min(frameSize.width, frameSize.height)
        return NSSize(width: side, height: side)
    }
}

private final class CameraPreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer

    init(frame: CGRect, session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.cornerRadius = frame.width / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        preview.videoGravity = .resizeAspectFill
        preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        preview.frame = bounds
    }
}
