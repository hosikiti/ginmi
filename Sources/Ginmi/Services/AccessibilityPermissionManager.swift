import ApplicationServices
import Combine
import Foundation

final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    func refreshStatus() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }
}
