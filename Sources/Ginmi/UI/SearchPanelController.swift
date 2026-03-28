import AppKit
import SwiftUI

@MainActor
final class SearchPanelController {
    private let viewModel: SearchPanelViewModel
    private let windowManager: any WindowManaging
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var pendingPresentationWorkItem: DispatchWorkItem?
    private var prefetchedCommandTabWindows: [WindowInfo] = []
    private var prefetchedCommandTabCurrentWindowID: Int?
    private var fastSearchActive = false
    private var commandTabActive = false
    private var commandTabInteracted = false
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
        let total = PerfLogger.start("panel.show_standard", details: "fast_search=\(fastSearchMode)")
        cancelPendingPresentationWorkItem()
        commandTabActive = false
        let panel = panel ?? makePanel()
        self.panel = panel
        self.fastSearchActive = fastSearchMode
        let currentWindowID = PerfLogger.measure("panel.standard.current_frontmost") {
            windowManager.currentFrontmostWindowID()
        }
        PerfLogger.measure("panel.standard.mark_frontmost") {
            viewModel.markFrontmostWindowAsUsed(windowID: currentWindowID)
        }
        PerfLogger.measure("panel.standard.viewmodel_show") {
            viewModel.show(resetQuery: !fastSearchMode, mode: .standard, initiallySelectedWindowID: currentWindowID)
        }

        let presentStage = PerfLogger.start("panel.standard.present")
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        PerfLogger.end("panel.standard.present", from: presentStage)
        PerfLogger.end("panel.show_standard", from: total)
    }

    func beginCommandTabSession() {
        let total = PerfLogger.start("panel.begin_command_tab_session")
        cancelPendingPresentationWorkItem()
        let panel = panel ?? makePanel()
        self.panel = panel
        fastSearchActive = false
        commandTabActive = true
        commandTabInteracted = false
        let predictedCurrentWindowID = prefetchedCommandTabCurrentWindowID ?? PerfLogger.measure("panel.command_tab.predict_frontmost") {
            windowManager.predictedFrontmostWindowID()
        }
        let prefetchedWindows = prefetchedCommandTabWindows.isEmpty ? windowManager.fetchCachedWindows() : prefetchedCommandTabWindows
        PerfLogger.measure("panel.command_tab.viewmodel_show_snapshot", details: "prefetched_count=\(prefetchedWindows.count)") {
            viewModel.show(
                resetQuery: true,
                mode: .commandTab,
                initiallySelectedWindowID: predictedCurrentWindowID,
                prefetchedWindows: prefetchedWindows.isEmpty ? nil : prefetchedWindows
            )
        }
        let presentStage = PerfLogger.start("panel.command_tab.present")
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        PerfLogger.end("panel.command_tab.present", from: presentStage)
        PerfLogger.end("panel.begin_command_tab_session", from: total)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.commandTabActive, self.panel?.isVisible == true else { return }

            let reconcileStart = PerfLogger.start("panel.command_tab.reconcile")
            let currentWindowID = PerfLogger.measure("panel.command_tab.current_frontmost") {
                self.windowManager.currentFrontmostWindowID()
            }
            PerfLogger.measure("panel.command_tab.mark_frontmost") {
                self.viewModel.markFrontmostWindowAsUsed(windowID: currentWindowID)
            }
            if !self.commandTabInteracted {
                PerfLogger.measure("panel.command_tab.viewmodel_show_fresh") {
                    self.viewModel.show(
                        resetQuery: false,
                        mode: .commandTab,
                        initiallySelectedWindowID: currentWindowID
                    )
                }
            }

            if self.debugCommandTab {
                if let selected = self.viewModel.selectedWindow() {
                    print(
                        "GINMI_COMMAND_TAB activeWindow id=\(selected.id) pid=\(selected.ownerPID) " +
                            "app=\(selected.ownerName) title=\"\(selected.displayTitle)\" bounds=\(selected.boundsSignature)"
                    )
                } else {
                    print("GINMI_COMMAND_TAB activeWindow unresolved currentWindowID=\(currentWindowID.map(String.init) ?? "nil")")
                }
            }
            PerfLogger.end("panel.command_tab.reconcile", from: reconcileStart)
        }
        pendingPresentationWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func prewarmCommandTabSnapshot() {
        let total = PerfLogger.start("panel.command_tab.prewarm_snapshot")
        windowManager.prewarmWindowCache()
        prefetchedCommandTabCurrentWindowID = PerfLogger.measure("panel.command_tab.prewarm_predict_frontmost") {
            windowManager.predictedFrontmostWindowID()
        }
        prefetchedCommandTabWindows = PerfLogger.measure("panel.command_tab.prewarm_cached_windows") {
            windowManager.fetchCachedWindows()
        }
        PerfLogger.end("panel.command_tab.prewarm_snapshot", from: total, details: "prefetched_count=\(prefetchedCommandTabWindows.count)")
    }

    func performQuickCommandTabSwitch() {
        let currentWindowID = windowManager.currentFrontmostWindowID()
        guard viewModel.prepareQuickCommandTabSwitch(initiallySelectedWindowID: currentWindowID) else { return }
        viewModel.commitSelection()
    }

    func cycleCommandTabSelection(forward: Bool) {
        guard commandTabActive else { return }
        commandTabInteracted = true
        viewModel.moveSelection(delta: forward ? 1 : -1)
    }

    func appendCommandTabQuery(_ text: String) {
        guard commandTabActive else { return }
        commandTabInteracted = true
        viewModel.appendQuery(text)
    }

    func deleteLastCommandTabQueryCharacter() {
        guard commandTabActive else { return }
        commandTabInteracted = true
        viewModel.deleteLastQueryCharacter()
    }

    func quitSelectedCommandTabApp() {
        guard commandTabActive else { return }
        commandTabInteracted = true
        viewModel.quitSelectedApp()
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
        cancelPendingPresentationWorkItem()
        panel?.orderOut(nil)
        viewModel.hide()
        fastSearchActive = false
        commandTabActive = false
        commandTabInteracted = false
        prefetchedCommandTabWindows = []
        prefetchedCommandTabCurrentWindowID = nil
    }

    func commitFastSearchIfNeeded() {
        guard fastSearchActive else { return }
        viewModel.commitSelection()
    }

    func cancelFastSearch() {
        guard fastSearchActive else { return }
        hidePanel()
    }

    func refreshVisibleResults() {
        guard panel?.isVisible == true else { return }
        let currentWindowID = windowManager.currentFrontmostWindowID()
        viewModel.refreshVisibleResults(initiallySelectedWindowID: currentWindowID)
    }

    func markFrontmostWindowAsUsed() {
        let currentWindowID = windowManager.currentFrontmostWindowID()
        viewModel.markFrontmostWindowAsUsed(windowID: currentWindowID)
    }

    func prewarmPanel() {
        if panel == nil {
            panel = makePanel()
        }
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

    private func cancelPendingPresentationWorkItem() {
        pendingPresentationWorkItem?.cancel()
        pendingPresentationWorkItem = nil
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
