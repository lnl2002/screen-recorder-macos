import AppKit
import SwiftUI

@MainActor
final class CountdownPanel {
    private let panel: NSPanel
    private let value = CountdownValue()

    init(displayID: CGDirectDisplayID) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main!
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CountdownView(value: value))
    }

    func run() async {
        panel.orderFrontRegardless()
        for number in stride(from: 3, through: 1, by: -1) {
            value.number = number
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil); panel.close()
    }
}

@MainActor private final class CountdownValue: ObservableObject { @Published var number = 3 }
private struct CountdownView: View {
    @ObservedObject var value: CountdownValue
    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
            Text("\(value.number)")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 20)
                .contentTransition(.numericText())
        }.ignoresSafeArea()
    }
}
