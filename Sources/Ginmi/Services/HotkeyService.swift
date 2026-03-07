import AppKit
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openSearch = Self("openSearch", default: .init(.space, modifiers: [.control]))
}

@MainActor
final class HotkeyService {
    private let panelController: SearchPanelController

    init(panelController: SearchPanelController) {
        self.panelController = panelController
    }

    func start() {
        KeyboardShortcuts.onKeyUp(for: .openSearch) { [weak self] in
            self?.panelController.togglePanel()
        }
    }
}
