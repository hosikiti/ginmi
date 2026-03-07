import AppKit
import SwiftUI

@MainActor
final class SearchPanelController {
    private let viewModel: SearchPanelViewModel
    private let windowManager: any WindowManaging
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var fastSearchActive = false
    private var commandTabActive = false
    private let debugCommandTab = ProcessInfo.processInfo.environment["GINMI_DEBUG_COMMAND_TAB"] == "1"

    init(viewModel: SearchPanelViewModel, windowManager: any WindowManaging) {
        self.viewModel = viewModel
        self.windowManager = windowManager
        viewModel.onCommitSelection = { [weak self] _, _ in
            self?.hidePanel()
        }
        viewModel.onCancel = { [weak self] in
            self?.hidePanel()
        }
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel(fastSearchMode: false)
        }
    }

    func showPanel(fastSearchMode: Bool) {
        commandTabActive = false
        let panel = panel ?? makePanel()
        self.panel = panel
        self.fastSearchActive = fastSearchMode
        viewModel.show(resetQuery: !fastSearchMode, mode: .standard)

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func beginCommandTabSession() {
        let panel = panel ?? makePanel()
        self.panel = panel
        fastSearchActive = false
        commandTabActive = true
        let currentWindowID = windowManager.currentFrontmostWindowID()
        viewModel.show(resetQuery: true, mode: .commandTab, initiallySelectedWindowID: currentWindowID)
        if debugCommandTab {
            if let selected = viewModel.selectedWindow() {
                print(
                    "GINMI_COMMAND_TAB activeWindow id=\(selected.id) pid=\(selected.ownerPID) " +
                        "app=\(selected.ownerName) title=\"\(selected.displayTitle)\" bounds=\(selected.boundsSignature)"
                )
            } else {
                print("GINMI_COMMAND_TAB activeWindow unresolved currentWindowID=\(currentWindowID.map(String.init) ?? "nil")")
            }
        }

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func cycleCommandTabSelection(forward: Bool) {
        guard commandTabActive else { return }
        viewModel.moveSelection(delta: forward ? 1 : -1)
    }

    func appendCommandTabQuery(_ text: String) {
        guard commandTabActive else { return }
        viewModel.appendQuery(text)
    }

    func deleteLastCommandTabQueryCharacter() {
        guard commandTabActive else { return }
        viewModel.deleteLastQueryCharacter()
    }

    func cancelCommandTabSession() {
        guard commandTabActive else { return }
        hidePanel()
    }

    func finishCommandTabSession() {
        guard commandTabActive else { return }
        if viewModel.hasSelection() {
            viewModel.commitSelection()
        } else {
            hidePanel()
        }
    }

    func hidePanel() {
        panel?.orderOut(nil)
        viewModel.hide()
        fastSearchActive = false
        commandTabActive = false
    }

    func commitFastSearchIfNeeded() {
        guard fastSearchActive else { return }
        viewModel.commitSelection()
    }

    func cancelFastSearch() {
        guard fastSearchActive else { return }
        hidePanel()
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: SearchPanelView(viewModel: viewModel))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = host

        installKeyboardMonitor()
        return panel
    }

    private func installKeyboardMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }

            if self.commandTabActive, event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 125: // Down
                    self.viewModel.moveSelection(delta: 1)
                    return nil
                case 126: // Up
                    self.viewModel.moveSelection(delta: -1)
                    return nil
                case 51: // Delete
                    self.viewModel.deleteLastQueryCharacter()
                    return nil
                case 53: // Escape
                    self.cancelCommandTabSession()
                    return nil
                default:
                    break
                }
            }

            switch event.keyCode {
            case 125: // Down
                self.viewModel.moveSelection(delta: 1)
                return nil
            case 126: // Up
                self.viewModel.moveSelection(delta: -1)
                return nil
            case 36: // Return
                self.viewModel.commitSelection()
                return nil
            case 53: // Escape
                self.viewModel.cancel()
                return nil
            default:
                return event
            }
        }
    }

    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
        let frame = targetScreen?.visibleFrame ?? .zero

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let x = frame.origin.x + (frame.width - panelWidth) / 2
        let y = frame.origin.y + (frame.height - panelHeight) / 2
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
