import AppKit
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openSearch = Self("openSearch", default: .init(.space, modifiers: [.control]))
}

@MainActor
final class HotkeyService {
    private let panelController: SearchPanelController
    private var flagsMonitor: Any?
    private let defaults: UserDefaults
    private let modifierKey = "fastSearchModifier"

    init(panelController: SearchPanelController, defaults: UserDefaults = .standard) {
        self.panelController = panelController
        self.defaults = defaults
    }

    func start() {
        KeyboardShortcuts.onKeyUp(for: .openSearch) { [weak self] in
            self?.panelController.togglePanel()
        }

        installModifierMonitor()
    }

    private func installModifierMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self else { return }
            let rawValue = self.defaults.string(forKey: self.modifierKey) ?? FastSearchModifier.fn.rawValue
            let modifier = FastSearchModifier(rawValue: rawValue) ?? .fn
            let isPressed = modifier.matches(event.modifierFlags)

            if isPressed {
                self.panelController.showPanel(fastSearchMode: true)
            } else {
                self.panelController.commitFastSearchIfNeeded()
            }
        }
    }
}
