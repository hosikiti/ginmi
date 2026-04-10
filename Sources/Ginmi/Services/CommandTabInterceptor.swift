import CoreGraphics
import AppKit
import Foundation

final class CommandTabInterceptor {
    private let defaultQuickSwitchEnabled = AppSettings.commandTabQuickSwitchEnabledDefault
    private let onCommandPressed: @MainActor () -> Void
    private let onSessionStart: @MainActor () -> Void
    private let onQuickSwitch: @MainActor () -> Void
    private let onCycleSelection: @MainActor (_ forward: Bool) -> Void
    private let onType: @MainActor (_ text: String) -> Void
    private let onDeleteBackward: @MainActor () -> Void
    private let onQuitSelection: @MainActor () -> Void
    private let onSessionCancel: @MainActor () -> Void
    private let onSessionEnd: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var commandTabSessionActive = false
    private var sessionStartTime: CFAbsoluteTime = 0
    private var panelPresented = false
    private var pendingPresentationWorkItem: DispatchWorkItem?
    private var commandKeyHeld = false
    private let debugCommandTab = ProcessInfo.processInfo.environment["GINMI_DEBUG_COMMAND_TAB"] == "1"

    init(
        onCommandPressed: @escaping @MainActor () -> Void,
        onSessionStart: @escaping @MainActor () -> Void,
        onQuickSwitch: @escaping @MainActor () -> Void,
        onCycleSelection: @escaping @MainActor (_ forward: Bool) -> Void,
        onType: @escaping @MainActor (_ text: String) -> Void,
        onDeleteBackward: @escaping @MainActor () -> Void,
        onQuitSelection: @escaping @MainActor () -> Void,
        onSessionCancel: @escaping @MainActor () -> Void,
        onSessionEnd: @escaping @MainActor () -> Void
    ) {
        self.onCommandPressed = onCommandPressed
        self.onSessionStart = onSessionStart
        self.onQuickSwitch = onQuickSwitch
        self.onCycleSelection = onCycleSelection
        self.onType = onType
        self.onDeleteBackward = onDeleteBackward
        self.onQuitSelection = onQuitSelection
        self.onSessionCancel = onSessionCancel
        self.onSessionEnd = onSessionEnd
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<CommandTabInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        cancelPendingPresentation()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            if type == .flagsChanged {
                let commandStillHeld = event.flags.contains(.maskCommand)
                if commandStillHeld && !commandKeyHeld && !commandTabSessionActive {
                    commandKeyHeld = true
                    let onCommandPressed = self.onCommandPressed
                    let start = PerfLogger.start("command.flags_changed", details: "event=command_down")
                    MainActor.assumeIsolated {
                        onCommandPressed()
                    }
                    PerfLogger.end("command.flags_changed", from: start, details: "event=command_down")
                } else if !commandStillHeld {
                    commandKeyHeld = false
                }
                if commandTabSessionActive && !commandStillHeld {
                    handleCommandRelease()
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isCommandTab = keyCode == 48 && flags.contains(.maskCommand)
        let isReverse = flags.contains(.maskShift)

        if isCommandTab {
            if commandTabSessionActive {
                ensureSessionPresented()
                let onCycleSelection = self.onCycleSelection
                MainActor.assumeIsolated {
                    onCycleSelection(!isReverse)
                }
            } else {
                beginSession()
            }
            return nil
        }

        guard commandTabSessionActive else {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == 53 { // Escape
            resetSessionState()
            let onSessionCancel = self.onSessionCancel
            if debugCommandTab {
                print("GINMI_COMMAND_TAB cancel")
            }
            MainActor.assumeIsolated {
                onSessionCancel()
            }
            return nil
        }

        if keyCode == 125 { // Down arrow
            ensureSessionPresented()
            let onCycleSelection = self.onCycleSelection
            MainActor.assumeIsolated {
                onCycleSelection(true)
            }
            return nil
        }

        if keyCode == 126 { // Up arrow
            ensureSessionPresented()
            let onCycleSelection = self.onCycleSelection
            MainActor.assumeIsolated {
                onCycleSelection(false)
            }
            return nil
        }

        if keyCode == 51 { // Delete
            ensureSessionPresented()
            let onDeleteBackward = self.onDeleteBackward
            MainActor.assumeIsolated {
                onDeleteBackward()
            }
            return nil
        }

        if keyCode == 12, flags.contains(.maskShift) { // Q
            ensureSessionPresented()
            let onQuitSelection = self.onQuitSelection
            MainActor.assumeIsolated {
                onQuitSelection()
            }
            return nil
        }

        if let text = extractTypeableText(from: event), !text.isEmpty {
            ensureSessionPresented()
            let onType = self.onType
            if debugCommandTab {
                print("GINMI_COMMAND_TAB type=\"\(text.lowercased())\" keyCode=\(keyCode)")
            }
            MainActor.assumeIsolated {
                onType(text.lowercased())
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func beginSession() {
        let start = PerfLogger.start("command_tab.begin_session")
        commandTabSessionActive = true
        sessionStartTime = CFAbsoluteTimeGetCurrent()
        panelPresented = false

        if debugCommandTab {
            print("GINMI_COMMAND_TAB start")
        }

        guard isQuickSwitchEnabled() else {
            presentSession()
            PerfLogger.end("command_tab.begin_session", from: start, details: "quick_switch=false")
            return
        }

        let holdDelayMs = commandTabHoldDelayMs()
        let workItem = DispatchWorkItem { [weak self] in
            self?.presentSession()
        }
        pendingPresentationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(holdDelayMs), execute: workItem)
        PerfLogger.end("command_tab.begin_session", from: start, details: "hold_delay_ms=\(holdDelayMs)")
    }

    private func ensureSessionPresented() {
        guard commandTabSessionActive, !panelPresented else { return }
        presentSession()
    }

    private func presentSession() {
        guard commandTabSessionActive, !panelPresented else { return }
        let start = PerfLogger.start("command_tab.present_session")
        cancelPendingPresentation()
        panelPresented = true
        let onSessionStart = self.onSessionStart
        MainActor.assumeIsolated {
            onSessionStart()
        }
        PerfLogger.end("command_tab.present_session", from: start)
    }

    private func handleCommandRelease() {
        let start = PerfLogger.start("command_tab.handle_release")
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - sessionStartTime) * 1000)
        let holdDelayMs = commandTabHoldDelayMs()

        if isQuickSwitchEnabled(), !panelPresented && elapsedMs < holdDelayMs {
            resetSessionState()
            let onQuickSwitch = self.onQuickSwitch
            if debugCommandTab {
                print("GINMI_COMMAND_TAB quickSwitch elapsedMs=\(elapsedMs)")
            }
            MainActor.assumeIsolated {
                onQuickSwitch()
            }
            PerfLogger.end("command_tab.handle_release", from: start, details: "path=quick_switch elapsed_ms=\(elapsedMs)")
            return
        }

        if !panelPresented {
            presentSession()
        }

        resetSessionState()
        let onSessionEnd = self.onSessionEnd
        if debugCommandTab {
            print("GINMI_COMMAND_TAB end")
        }
        MainActor.assumeIsolated {
            onSessionEnd()
        }
        PerfLogger.end("command_tab.handle_release", from: start, details: "path=panel_presented elapsed_ms=\(elapsedMs)")
    }

    private func cancelPendingPresentation() {
        pendingPresentationWorkItem?.cancel()
        pendingPresentationWorkItem = nil
    }

    private func resetSessionState() {
        cancelPendingPresentation()
        commandTabSessionActive = false
        panelPresented = false
        sessionStartTime = 0
        commandKeyHeld = false
    }

    private func commandTabHoldDelayMs() -> Int {
        let configured = UserDefaults.standard.object(forKey: AppSettings.commandTabHoldDelayMsKey) as? Int
        return max(0, configured ?? AppSettings.commandTabHoldDelayMsDefault)
    }

    private func isQuickSwitchEnabled() -> Bool {
        let configured = UserDefaults.standard.object(forKey: AppSettings.commandTabQuickSwitchEnabledKey) as? Bool
        return configured ?? defaultQuickSwitchEnabled
    }

    private func extractTypeableText(from event: CGEvent) -> String? {
        if let nsEvent = NSEvent(cgEvent: event),
           let chars = nsEvent.charactersIgnoringModifiers,
           !chars.isEmpty
        {
            let allowed = CharacterSet.alphanumerics.union(.whitespaces)
            let filteredScalars = chars.unicodeScalars.filter { allowed.contains($0) }
            if !filteredScalars.isEmpty {
                return String(String.UnicodeScalarView(filteredScalars))
            }
        }

        return keyCodeFallback(Int(event.getIntegerValueField(.keyboardEventKeycode)))
    }

    private func keyCodeFallback(_ keyCode: Int) -> String? {
        let letterMap: [Int: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
            34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m"
        ]
        let digitMap: [Int: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0"
        ]

        if keyCode == 49 {
            return " "
        }
        if let letter = letterMap[keyCode] {
            return letter
        }
        return digitMap[keyCode]
    }
}
