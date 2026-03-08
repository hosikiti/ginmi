import AppKit
import XCTest
@testable import Ginmi

@MainActor
final class SearchPanelViewModelTests: XCTestCase {
    func testCommandTabQueryMutationFiltersResultsImmediately() {
        let windows = [
            makeWindow(id: 1, app: "Cursor", title: "sse.service.ts - backend-revamp"),
            makeWindow(id: 2, app: "ChatGPT", title: "ChatGPT"),
            makeWindow(id: 3, app: "Arc", title: "MK TODO - Todoist"),
            makeWindow(id: 4, app: "Arc", title: "Trump Threatens Spain Trade Over Iran Bases - Grok")
        ]
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        let store = SearchShortcutStore(defaults: defaults)
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            searcher: FuzzySearcher(),
            shortcutsStore: store,
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab)
        XCTAssertEqual(viewModel.results.count, 4)

        viewModel.query = "arc"

        XCTAssertEqual(viewModel.results.compactMap(windowOwnerName), ["Arc", "Arc"])
        XCTAssertTrue(viewModel.results.allSatisfy {
            guard let window = extractWindow(from: $0) else { return false }
            return "\(window.ownerName) \(window.displayTitle)".lowercased().contains("arc")
        })
    }

    func testCommandTabShowPrioritizesAndSelectsCurrentWindow() {
        let windows = [
            makeWindow(id: 1, app: "Arc", title: "Mail"),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal"),
            makeWindow(id: 3, app: "Code", title: "Ginmi")
        ]
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab, initiallySelectedWindowID: 2)

        XCTAssertEqual(viewModel.results.compactMap(windowID), [2, 1, 3])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testFallsBackToInstalledAppsWhenNoWindowsMatchAndSettingEnabled() {
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "searchInstalledAppsFallbackEnabled")
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: [makeWindow(id: 1, app: "Ghostty", title: "Terminal")]),
            installedAppManager: FakeInstalledAppManager(apps: [
                InstalledAppInfo(name: "Calendar", bundleIdentifier: "com.apple.Calendar", url: URL(fileURLWithPath: "/Applications/Calendar.app")),
                InstalledAppInfo(name: "Calculator", bundleIdentifier: "com.apple.Calculator", url: URL(fileURLWithPath: "/Applications/Calculator.app"))
            ]),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .standard)
        viewModel.query = "cal"
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(viewModel.results.count, 2)
        XCTAssertTrue(viewModel.results.allSatisfy {
            if case .app = $0.kind { return true }
            return false
        })
    }

    func testStandardSearchShowsWindowsFirstThenInstalledApps() {
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "searchInstalledAppsFallbackEnabled")
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: [makeWindow(id: 1, app: "Arc", title: "Mail")]),
            installedAppManager: FakeInstalledAppManager(apps: [
                InstalledAppInfo(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", url: URL(fileURLWithPath: "/Applications/Arc.app")),
                InstalledAppInfo(name: "Archive Utility", bundleIdentifier: "com.apple.archiveutility", url: URL(fileURLWithPath: "/System/Applications/Archive Utility.app"))
            ]),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .standard)
        viewModel.query = "arc"
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(windowID(from: viewModel.results.first!), 1)
        XCTAssertEqual(viewModel.results.dropFirst().compactMap(appName), ["Arc", "Archive Utility"])
    }

    func testCommandTabShowsWindowsFirstThenInstalledApps() {
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "searchInstalledAppsFallbackEnabled")
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: [makeWindow(id: 1, app: "Arc", title: "Mail")]),
            installedAppManager: FakeInstalledAppManager(apps: [
                InstalledAppInfo(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", url: URL(fileURLWithPath: "/Applications/Arc.app")),
                InstalledAppInfo(name: "Archive Utility", bundleIdentifier: "com.apple.archiveutility", url: URL(fileURLWithPath: "/System/Applications/Archive Utility.app"))
            ]),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab)
        viewModel.query = "arc"

        XCTAssertEqual(windowID(from: viewModel.results.first!), 1)
        XCTAssertEqual(viewModel.results.dropFirst().compactMap(appName), ["Arc", "Archive Utility"])
    }

    func testDoesNotShowInstalledAppsWhenFallbackSettingDisabled() {
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(false, forKey: "searchInstalledAppsFallbackEnabled")
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: [makeWindow(id: 1, app: "Ghostty", title: "Terminal")]),
            installedAppManager: FakeInstalledAppManager(apps: [
                InstalledAppInfo(name: "Calendar", bundleIdentifier: "com.apple.Calendar", url: URL(fileURLWithPath: "/Applications/Calendar.app"))
            ]),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .standard)
        viewModel.query = "cal"
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertTrue(viewModel.results.isEmpty)
    }

    private func makeWindow(id: Int, app: String, title: String) -> WindowInfo {
        WindowInfo(
            id: id,
            ownerPID: 1,
            ownerName: app,
            ownerBundleID: "test.\(app.lowercased())",
            title: title,
            layer: 0,
            isOnScreen: true,
            alpha: 1.0,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    private func extractWindow(from result: SearchResultItem) -> WindowInfo? {
        if case let .window(window) = result.kind {
            return window
        }
        return nil
    }

    private func windowOwnerName(from result: SearchResultItem) -> String? {
        extractWindow(from: result)?.ownerName
    }

    private func windowID(from result: SearchResultItem) -> Int? {
        extractWindow(from: result)?.id
    }

    private func appName(from result: SearchResultItem) -> String? {
        if case let .app(app) = result.kind {
            return app.name
        }
        return nil
    }
}

private final class FakeWindowManager: WindowManaging {
    let windows: [WindowInfo]

    init(windows: [WindowInfo]) {
        self.windows = windows
    }

    func fetchAllWindows() -> [WindowInfo] {
        windows
    }

    func icon(for window: WindowInfo) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16))
    }

    func currentFrontmostWindowID() -> Int? {
        windows.first?.id
    }

    func activate(window: WindowInfo) -> Bool {
        true
    }
}

private final class FakeInstalledAppManager: InstalledAppManaging {
    let apps: [InstalledAppInfo]

    init(apps: [InstalledAppInfo]) {
        self.apps = apps
    }

    func installedApps() -> [InstalledAppInfo] {
        apps
    }

    func icon(for app: InstalledAppInfo) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16))
    }

    func launch(app: InstalledAppInfo) -> Bool {
        true
    }
}
