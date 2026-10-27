import AppKit
import SwiftUI
import RecorderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = RecorderModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let root = NSMenuItem()
        let items = NSMenu()
        items.addItem(withTitle: model.tr("About Screen Recorder"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        items.addItem(.separator())
        items.addItem(withTitle: model.tr("Quit Screen Recorder"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = items; appMenu.addItem(root)
        NSApp.mainMenu = appMenu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Screen Recorder")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        statusItem = item
        showWindow()
    }

    @objc private func showWindow() {
        if window == nil {
            let view = ScrollView { RecorderView(model: model) }.frame(width: 720)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Screen Recorder"
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 720, height: 680)
            window.maxSize = NSSize(width: 720, height: 1100)
            window.isReleasedWhenClosed = false
            window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(model.tr("Show recorder"), action: #selector(showWindow), to: menu)
        if model.phase == .recording {
            add(model.tr("Stop & export"), action: #selector(stopRecording), to: menu)
        } else if model.phase == .exporting {
            add(model.tr("Cancel export"), action: #selector(cancelExport), to: menu)
        } else if model.canRecord {
            add(model.tr("Start recording"), action: #selector(startRecording), to: menu)
        }
        menu.addItem(.separator())
        if !model.busy { add(model.tr("Quit Screen Recorder"), action: #selector(quit), to: menu) }
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    @objc private func startRecording() { Task { await model.start() } }
    @objc private func stopRecording() { Task { await model.stop() } }
    @objc private func cancelExport() { model.cancelExport() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = model.tr("Finish your recording first")
        alert.informativeText = model.tr("Stop the recording or cancel the export before quitting. Your original recording will be kept.")
        alert.addButton(withTitle: model.tr("Keep recorder open"))
        alert.runModal()
        return .terminateCancel
    }
}

if CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--capture-test") || CommandLine.arguments.contains("--reexport") {
    _ = NSApplication.shared
    Task { @MainActor in
        do {
            if let index = CommandLine.arguments.firstIndex(of: "--reexport") {
                guard index + 1 < CommandLine.arguments.count else { throw RecorderError.message("--reexport requires a session folder.") }
                let session = try RecordingSession.open(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                var settings = session.manifest.settings
                if CommandLine.arguments.contains("--smooth") {
                    settings.response = 0.75; settings.hold = 2; settings.lead = 0.35; settings.deadZone = 0.12
                }
                let quality: RecorderCore.ExportQuality = CommandLine.arguments.contains("--720p") ? .compact : .source
                let output = try await VideoExporter().export(session, settings: settings, quality: quality)
                print("Exported: \(output.path)")
            } else if CommandLine.arguments.contains("--capture-test") { try await SmokeTest.capture() }
            else { try await SmokeTest.run() }
            exit(0)
        } catch {
            fputs("Smoke test failed: \(error)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
