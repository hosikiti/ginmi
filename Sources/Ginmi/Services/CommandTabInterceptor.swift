import CoreGraphics
import AppKit
import Foundation

final class CommandTabInterceptor {
    private let onSessionStart: @MainActor () -> Void
    private let onCycleSelection: @MainActor (_ forward: Bool) -> Void
    private let onType: @MainActor (_ text: String) -> Void
    private let onDeleteBackward: @MainActor () -> Void
    private let onQuitSelection: @MainActor () -> Void
    private let onSessionCancel: @MainActor () -> Void
    private let onSessionEnd: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var commandTabSessionActive = false
    private let debugCommandTab = ProcessInfo.processInfo.environment["GINMI_DEBUG_COMMAND_TAB"] == "1"

    init(
        onSessionStart: @escaping @MainActor () -> Void,
        onCycleSelection: @escaping @MainActor (_ forward: Bool) -> Void,
        onType: @escaping @MainActor (_ text: String) -> Void,
        onDeleteBackward: @escaping @MainActor () -> Void,
        onQuitSelection: @escaping @MainActor () -> Void,
        onSessionCancel: @escaping @MainActor () -> Void,
        onSessionEnd: @escaping @MainActor () -> Void
    ) {
        self.onSessionStart = onSessionStart
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
                if commandTabSessionActive && !commandStillHeld {
                    commandTabSessionActive = false
                    let onSessionEnd = self.onSessionEnd
                    if debugCommandTab {
                        print("GINMI_COMMAND_TAB end")
                    }
                    MainActor.assumeIsolated {
                        onSessionEnd()
                    }
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
                let onCycleSelection = self.onCycleSelection
                MainActor.assumeIsolated {
                    onCycleSelection(!isReverse)
                }
            } else {
                commandTabSessionActive = true
                let onSessionStart = self.onSessionStart
                if debugCommandTab {
                    print("GINMI_COMMAND_TAB start")
                }
                MainActor.assumeIsolated {
                    onSessionStart()
                }
            }
            return nil
        }

        guard commandTabSessionActive else {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == 53 { // Escape
            commandTabSessionActive = false
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
            let onCycleSelection = self.onCycleSelection
            MainActor.assumeIsolated {
                onCycleSelection(true)
            }
            return nil
        }

        if keyCode == 126 { // Up arrow
            let onCycleSelection = self.onCycleSelection
            MainActor.assumeIsolated {
                onCycleSelection(false)
            }
            return nil
        }

        if keyCode == 51 { // Delete
            let onDeleteBackward = self.onDeleteBackward
            MainActor.assumeIsolated {
                onDeleteBackward()
            }
            return nil
        }

        if keyCode == 12, flags.contains(.maskShift) { // Q
            let onQuitSelection = self.onQuitSelection
            MainActor.assumeIsolated {
                onQuitSelection()
            }
            return nil
        }

        if let text = extractTypeableText(from: event), !text.isEmpty {
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
