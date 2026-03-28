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
            appTerminator: FakeAppTerminator(),
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
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab, initiallySelectedWindowID: 2)

        XCTAssertEqual(viewModel.results.compactMap(windowID), [2, 1, 3])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testPrepareQuickCommandTabSwitchSelectsPreviouslyUsedWindow() {
        let windows = [
            makeWindow(id: 1, app: "Arc", title: "Mail"),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal"),
            makeWindow(id: 3, app: "Code", title: "Ginmi")
        ]
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(
            [
                windows[1].identifier: 20,
                windows[2].identifier: 10
            ],
            forKey: "windowLastUsed"
        )
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        let canQuickSwitch = viewModel.prepareQuickCommandTabSwitch(initiallySelectedWindowID: 1)

        XCTAssertTrue(canQuickSwitch)
        XCTAssertEqual(viewModel.results.compactMap(windowID), [1, 2, 3])
        XCTAssertEqual(viewModel.selectedIndex, 1)
    }

    func testCommandTabShowOrdersRemainingWindowsByLastUsedDescending() {
        let windows = [
            makeWindow(id: 1, app: "Arc", title: "Mail"),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal"),
            makeWindow(id: 3, app: "Code", title: "Ginmi"),
            makeWindow(id: 4, app: "Cursor", title: "backend-revamp")
        ]
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(
            [
                windows[1].identifier: 10,
                windows[2].identifier: 30,
                windows[3].identifier: 20
            ],
            forKey: "windowLastUsed"
        )
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab, initiallySelectedWindowID: 1)

        XCTAssertEqual(viewModel.results.compactMap(windowID), [1, 3, 4, 2])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testStandardShowOrdersEmptyQueryByLastUsedDescendingAfterCurrentWindow() {
        let windows = [
            makeWindow(id: 1, app: "Arc", title: "Mail"),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal"),
            makeWindow(id: 3, app: "Code", title: "Ginmi")
        ]
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set(
            [
                windows[1].identifier: 10,
                windows[2].identifier: 20
            ],
            forKey: "windowLastUsed"
        )
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .standard, initiallySelectedWindowID: 1)

        XCTAssertEqual(viewModel.results.compactMap(windowID), [1, 3, 2])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testMarkFrontmostWindowAsUsedUpdatesNextInitialOrdering() {
        let windows = [
            makeWindow(id: 1, app: "Arc", title: "Mail"),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal"),
            makeWindow(id: 3, app: "Code", title: "Ginmi")
        ]
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.markFrontmostWindowAsUsed(windowID: 3)
        viewModel.show(resetQuery: true, mode: .standard, initiallySelectedWindowID: 1)

        XCTAssertEqual(viewModel.results.compactMap(windowID), [1, 3, 2])
    }

    func testInitialOrderingUsesStableWindowIdentifierWhenTitleChanges() {
        let oldTitleWindow = makeWindow(id: 2, app: "Arc", title: "Inbox")
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        let shortcutsStore = SearchShortcutStore(defaults: defaults)
        shortcutsStore.touchRecency(for: oldTitleWindow.identifier, at: Date(timeIntervalSince1970: 200))

        let windows = [
            makeWindow(id: 1, app: "Ghostty", title: "Terminal"),
            makeWindow(id: 2, app: "Arc", title: "Inbox (Updated)")
        ]
        let viewModel = SearchPanelViewModel(
            windowManager: FakeWindowManager(windows: windows),
            installedAppManager: FakeInstalledAppManager(apps: []),
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: shortcutsStore,
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .standard, initiallySelectedWindowID: 1)

        XCTAssertEqual(viewModel.results.compactMap(windowID), [1, 2])
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
            appTerminator: FakeAppTerminator(),
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
            appTerminator: FakeAppTerminator(),
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
            appTerminator: FakeAppTerminator(),
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
            appTerminator: FakeAppTerminator(),
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .standard)
        viewModel.query = "cal"
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertTrue(viewModel.results.isEmpty)
    }

    func testQuitSelectedAppTerminatesSelectedWindowOwnerAndRefreshesResults() {
        let windowManager = FakeWindowManager(windows: [
            makeWindow(id: 1, app: "Arc", title: "Mail", pid: 11),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal", pid: 22)
        ])
        let appTerminator = FakeAppTerminator { terminatedPID in
            windowManager.windows.removeAll { $0.ownerPID == terminatedPID }
        }
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        let viewModel = SearchPanelViewModel(
            windowManager: windowManager,
            installedAppManager: FakeInstalledAppManager(apps: []),
            appTerminator: appTerminator,
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab, initiallySelectedWindowID: 1)
        viewModel.quitSelectedApp()

        XCTAssertEqual(appTerminator.terminatedWindowPIDs, [11])
        XCTAssertEqual(viewModel.results.compactMap(windowID), [2])
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testQuitSelectedAppSuppressesAppImmediatelyEvenIfWindowSourceStillContainsIt() {
        let windowManager = FakeWindowManager(windows: [
            makeWindow(id: 1, app: "Arc", title: "Mail", pid: 11),
            makeWindow(id: 2, app: "Ghostty", title: "Terminal", pid: 22)
        ])
        let appTerminator = FakeAppTerminator()
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        let viewModel = SearchPanelViewModel(
            windowManager: windowManager,
            installedAppManager: FakeInstalledAppManager(apps: [
                InstalledAppInfo(name: "Arc", bundleIdentifier: "test.arc", url: URL(fileURLWithPath: "/Applications/Arc.app"))
            ]),
            appTerminator: appTerminator,
            searcher: FuzzySearcher(),
            shortcutsStore: SearchShortcutStore(defaults: defaults),
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab, initiallySelectedWindowID: 1)
        viewModel.quitSelectedApp()

        XCTAssertEqual(appTerminator.terminatedWindowPIDs, [11])
        XCTAssertEqual(viewModel.results.compactMap(windowID), [2])
        XCTAssertFalse(viewModel.results.contains { result in
            if case let .app(app) = result.kind {
                return app.name == "Arc"
            }
            return false
        })
    }

    private func makeWindow(id: Int, app: String, title: String, pid: pid_t = 1) -> WindowInfo {
        WindowInfo(
            id: id,
            ownerPID: pid,
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
    var windows: [WindowInfo]

    init(windows: [WindowInfo]) {
        self.windows = windows
    }

    func fetchAllWindows() -> [WindowInfo] {
        windows
    }

    func fetchCachedWindows() -> [WindowInfo] {
        windows
    }

    func predictedFrontmostWindowID() -> Int? {
        windows.first?.id
    }

    func prewarmWindowCache() {}

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

private final class FakeAppTerminator: AppTerminating {
    private let onTerminateWindow: ((pid_t) -> Void)?
    private let onTerminateApp: ((String) -> Void)?
    private(set) var terminatedWindowPIDs: [pid_t] = []
    private(set) var terminatedAppBundleIDs: [String] = []

    init(
        onTerminateWindow: ((pid_t) -> Void)? = nil,
        onTerminateApp: ((String) -> Void)? = nil
    ) {
        self.onTerminateWindow = onTerminateWindow
        self.onTerminateApp = onTerminateApp
    }

    func terminate(window: WindowInfo) -> Bool {
        terminatedWindowPIDs.append(window.ownerPID)
        onTerminateWindow?(window.ownerPID)
        return true
    }

    func terminate(app: InstalledAppInfo) -> Bool {
        terminatedAppBundleIDs.append(app.bundleIdentifier)
        onTerminateApp?(app.bundleIdentifier)
        return true
    }
}
