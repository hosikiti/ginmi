import AppKit
import SwiftUI

@main
struct GinmiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let shortcutsStore = SearchShortcutStore()
    private let permissionManager = AccessibilityPermissionManager()
    private let windowManager = WindowManager()
    private let installedAppManager = InstalledAppManager()

    private lazy var viewModel = SearchPanelViewModel(
        windowManager: windowManager,
        installedAppManager: installedAppManager,
        searcher: FuzzySearcher(),
        shortcutsStore: shortcutsStore
    )
    private lazy var panelController = SearchPanelController(viewModel: viewModel, windowManager: windowManager)
    private lazy var hotkeyService = HotkeyService(panelController: panelController)
    private lazy var commandTabInterceptor = CommandTabInterceptor(
        onSessionStart: { [weak self] in
            self?.panelController.beginCommandTabSession()
        },
        onCycleSelection: { [weak self] forward in
            self?.panelController.cycleCommandTabSelection(forward: forward)
        },
        onType: { [weak self] text in
            self?.panelController.appendCommandTabQuery(text)
        },
        onDeleteBackward: { [weak self] in
            self?.panelController.deleteLastCommandTabQueryCharacter()
        },
        onSessionCancel: { [weak self] in
            self?.panelController.cancelCommandTabSession()
        },
        onSessionEnd: { [weak self] in
            self?.panelController.finishCommandTabSession()
        }
    )
    private lazy var settingsWindowController = SettingsWindowController(shortcutsStore: shortcutsStore)
    private lazy var statusBarController = StatusBarController(
        panelController: panelController,
        openSettingsHandler: { [weak self] in
            self?.settingsWindowController.show()
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.orderOut(nil) }

        statusBarController.start()
        hotkeyService.start()
        commandTabInterceptor.start()
        ensureAccessibilityPermission()
    }

    private func ensureAccessibilityPermission() {
        permissionManager.refreshStatus()
        guard !permissionManager.isTrusted else { return }

        let alert = NSAlert()
        alert.messageText = "Ginmi needs Accessibility access"
        alert.informativeText = "Ginmi uses Accessibility to enumerate and focus individual windows across apps and spaces."
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            permissionManager.requestIfNeeded()
        }
    }
}
