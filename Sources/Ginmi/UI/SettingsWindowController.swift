import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(shortcutsStore: SearchShortcutStore) {
        let rootView = SettingsView(shortcutsStore: shortcutsStore)
        let host = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: host)
        window.title = "Ginmi Settings"
        window.setContentSize(NSSize(width: 680, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
