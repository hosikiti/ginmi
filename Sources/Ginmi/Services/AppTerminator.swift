import AppKit
import Foundation

protocol AppTerminating {
    @discardableResult
    func terminate(window: WindowInfo) -> Bool

    @discardableResult
    func terminate(app: InstalledAppInfo) -> Bool
}

final class AppTerminator: AppTerminating {
    @discardableResult
    func terminate(window: WindowInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else {
            return false
        }
        return app.terminate()
    }

    @discardableResult
    func terminate(app: InstalledAppInfo) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications.filter { runningApp in
            if !app.bundleIdentifier.isEmpty {
                return runningApp.bundleIdentifier == app.bundleIdentifier
            }
            return runningApp.localizedName == app.name
        }

        guard !runningApps.isEmpty else { return false }
        return runningApps.reduce(false) { didTerminate, runningApp in
            runningApp.terminate() || didTerminate
        }
    }
}
