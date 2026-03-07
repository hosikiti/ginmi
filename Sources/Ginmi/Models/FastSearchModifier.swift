import AppKit
import Foundation

enum FastSearchModifier: String, CaseIterable, Identifiable {
    case fn
    case option
    case command
    case shift
    case control

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: return "Fn"
        case .option: return "Option"
        case .command: return "Command"
        case .shift: return "Shift"
        case .control: return "Control"
        }
    }

    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .fn:
            return flags.contains(.function)
        case .option:
            return flags.contains(.option)
        case .command:
            return flags.contains(.command)
        case .shift:
            return flags.contains(.shift)
        case .control:
            return flags.contains(.control)
        }
    }
}
