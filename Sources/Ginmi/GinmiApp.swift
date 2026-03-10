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
    private enum DefaultsKey {
        static let commandTabQuickSwitchThresholdMs = "commandTabQuickSwitchThresholdMs"
        static let commandTabQuickSwitchThresholdMigrated = "commandTabQuickSwitchThresholdMigrated"
    }

    let shortcutsStore = SearchShortcutStore()
    private let permissionManager = AccessibilityPermissionManager()
    private let windowManager = WindowManager()
    private let installedAppManager = InstalledAppManager()
    private let appTerminator = AppTerminator()
    private var workspaceNotificationObservers: [NSObjectProtocol] = []

    private lazy var viewModel = SearchPanelViewModel(
        windowManager: windowManager,
        installedAppManager: installedAppManager,
        appTerminator: appTerminator,
        searcher: FuzzySearcher(),
        shortcutsStore: shortcutsStore
    )
    private lazy var panelController = SearchPanelController(viewModel: viewModel, windowManager: windowManager)
    private lazy var hotkeyService = HotkeyService(panelController: panelController)
    private lazy var commandTabInterceptor = CommandTabInterceptor(
        onSessionStart: { [weak self] in
            self?.panelController.beginCommandTabSession()
        },
        onQuickSwitch: { [weak self] in
            self?.panelController.performQuickCommandTabSwitch()
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
        onQuitSelection: { [weak self] in
            self?.panelController.quitSelectedCommandTabApp()
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
        migrateCommandTabQuickSwitchThresholdIfNeeded()
        windowManager.prewarmWindowCache()

        statusBarController.start()
        hotkeyService.start()
        commandTabInterceptor.start()
        startObservingWorkspaceChanges()
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

    private func migrateCommandTabQuickSwitchThresholdIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.commandTabQuickSwitchThresholdMigrated) else { return }

        if let configured = defaults.object(forKey: DefaultsKey.commandTabQuickSwitchThresholdMs) as? Int,
           configured == 100
        {
            defaults.set(70, forKey: DefaultsKey.commandTabQuickSwitchThresholdMs)
        }

        defaults.set(true, forKey: DefaultsKey.commandTabQuickSwitchThresholdMigrated)
    }

    private func startObservingWorkspaceChanges() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        workspaceNotificationObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if name == NSWorkspace.didActivateApplicationNotification {
                        self?.scheduleActiveWindowTracking()
                    } else {
                        self?.scheduleWindowRefreshAfterWorkspaceChange()
                    }
                }
            }
        }
    }

    private func scheduleActiveWindowTracking() {
        for delay in [0.03, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.panelController.markFrontmostWindowAsUsed()
                self.panelController.refreshVisibleResults()
            }
        }
    }

    private func scheduleWindowRefreshAfterWorkspaceChange() {
        windowManager.invalidateWindowCache()
        windowManager.prewarmWindowCache()

        // Launch/terminate notifications can arrive before the app's visible windows settle.
        for delay in [0.15, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.windowManager.prewarmWindowCache()
                self.panelController.refreshVisibleResults()
            }
        }
    }
}
