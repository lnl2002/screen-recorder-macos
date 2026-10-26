import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = RecorderModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let root = NSMenuItem()
        let items = NSMenu()
        items.addItem(withTitle: "About Screen Recorder", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        items.addItem(.separator())
        items.addItem(withTitle: "Quit Screen Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            let view = ScrollView { RecorderView(model: model) }.frame(width: 560)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 750),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Screen Recorder"
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 560, height: 600)
            window.maxSize = NSSize(width: 560, height: 1000)
            window.isReleasedWhenClosed = false
            window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Show recorder", action: #selector(showWindow), to: menu)
        if model.phase == .recording {
            add("Stop & export", action: #selector(stopRecording), to: menu)
        } else if model.phase == .exporting {
            add("Cancel export", action: #selector(cancelExport), to: menu)
        } else if model.canRecord {
            add("Start recording", action: #selector(startRecording), to: menu)
        }
        menu.addItem(.separator())
        if !model.busy { add("Quit Screen Recorder", action: #selector(quit), to: menu) }
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
        alert.messageText = "Finish your recording first"
        alert.informativeText = "Stop the recording or cancel the export before quitting. Your original recording will be kept."
        alert.addButton(withTitle: "Keep recorder open")
        alert.runModal()
        return .terminateCancel
    }
}

if CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--capture-test") {
    _ = NSApplication.shared
    Task { @MainActor in
        do {
            if CommandLine.arguments.contains("--capture-test") { try await SmokeTest.capture() }
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
