import AppKit
import Foundation

protocol InstalledAppManaging {
    func installedApps() -> [InstalledAppInfo]
    func icon(for app: InstalledAppInfo) -> NSImage
    @discardableResult
    func launch(app: InstalledAppInfo) -> Bool
}

final class InstalledAppManager: InstalledAppManaging {
    private var cachedApps: [InstalledAppInfo] = []
    private var cacheDate: Date?

    func installedApps() -> [InstalledAppInfo] {
        if let cacheDate, Date().timeIntervalSince(cacheDate) < 30 {
            return cachedApps
        }

        let appDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
        ]
        var discovered: [InstalledAppInfo] = []
        var seenPaths = Set<String>()

        for directory in appDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app", seenPaths.insert(url.path).inserted else { continue }
                let bundle = Bundle(url: url)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let bundleID = bundle?.bundleIdentifier ?? ""
                discovered.append(InstalledAppInfo(name: name, bundleIdentifier: bundleID, url: url))
            }
        }

        cachedApps = discovered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        cacheDate = Date()
        return cachedApps
    }

    func icon(for app: InstalledAppInfo) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.url.path)
    }

    @discardableResult
    func launch(app: InstalledAppInfo) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                NSLog("Ginmi failed to launch app at %@: %@", app.url.path, error.localizedDescription)
            }
        }
        return true
    }
}
