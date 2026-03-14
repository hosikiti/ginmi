import AppKit
import Foundation

@MainActor
final class StatusBarController: NSObject {
    private let panelController: SearchPanelController
    private let openSettingsHandler: () -> Void
    private var statusItem: NSStatusItem?

    init(panelController: SearchPanelController, openSettingsHandler: @escaping () -> Void) {
        self.panelController = panelController
        self.openSettingsHandler = openSettingsHandler
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = GinmiIconFactory.statusBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Ginmi"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Search", action: #selector(openSearch), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Ginmi", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc
    private func openSearch() {
        panelController.showPanel(fastSearchMode: false)
    }

    @objc
    private func openSettings() {
        openSettingsHandler()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
