import XCTest
@testable import Ginmi

final class WindowManagerTests: XCTestCase {
    func testFilterGenericUntitledCompanionsDropsUntitledSiblingWhenTitledWindowExists() {
        let manager = WindowManager()
        let windows = [
            makeWindow(id: 1, pid: 100, app: "Ghostty", title: "", bounds: CGRect(x: 0, y: 0, width: 500, height: 500)),
            makeWindow(id: 2, pid: 100, app: "Ghostty", title: "swift run Ginmi", bounds: CGRect(x: 10, y: 10, width: 800, height: 600)),
            makeWindow(id: 3, pid: 200, app: "Finder", title: "", bounds: CGRect(x: 20, y: 20, width: 900, height: 700))
        ]

        let filtered = manager.filterGenericUntitledCompanions(windows)

        XCTAssertEqual(filtered.map(\.id), [2, 3])
    }

    func testCollapseDuplicateTitledWindowsKeepsSingleVisibleForkStyleWindow() {
        let manager = WindowManager()
        let windows = [
            makeWindow(id: 4724, pid: 53899, app: "Fork", title: "ginmi", bounds: CGRect(x: 0, y: 38, width: 1476, height: 944), isOnScreen: false),
            makeWindow(id: 4725, pid: 53899, app: "Fork", title: "ginmi", bounds: CGRect(x: 0, y: 38, width: 1476, height: 944), isOnScreen: true),
            makeWindow(id: 4726, pid: 53899, app: "Fork", title: "ginmi", bounds: CGRect(x: 0, y: 38, width: 1476, height: 944), isOnScreen: false)
        ]

        let collapsed = manager.collapseDuplicateTitledWindows(windows)

        XCTAssertEqual(collapsed.map(\.id), [4725])
    }

    func testShouldKeepWindowDropsAutofillHelpers() {
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.removeObject(forKey: "excludedWindowTitleKeywords")
        let manager = WindowManager(defaults: defaults)
        let autofillByName = makeWindow(
            id: 1,
            pid: 300,
            app: "AutoFill",
            title: "AutoFill",
            bounds: CGRect(x: 10, y: 10, width: 400, height: 200),
            bundleID: "com.apple.some.helper"
        )
        let autofillByBundle = makeWindow(
            id: 2,
            pid: 301,
            app: "Some Helper",
            title: "AutoFill UI",
            bounds: CGRect(x: 10, y: 10, width: 400, height: 200),
            bundleID: "com.apple.autofillui"
        )
        let normalWindow = makeWindow(
            id: 3,
            pid: 302,
            app: "Arc",
            title: "Inbox",
            bounds: CGRect(x: 10, y: 10, width: 1200, height: 900),
            bundleID: "company.thebrowser.Browser"
        )

        XCTAssertFalse(manager.shouldKeepWindow(autofillByName))
        XCTAssertFalse(manager.shouldKeepWindow(autofillByBundle))
        XCTAssertTrue(manager.shouldKeepWindow(normalWindow))
    }

    func testShouldKeepWindowRespectsConfiguredExcludedKeywords() {
        let defaults = UserDefaults(suiteName: "GinmiTests-\(UUID().uuidString)")!
        defaults.set("floating panel,private", forKey: "excludedWindowTitleKeywords")
        let manager = WindowManager(defaults: defaults)
        let excluded = makeWindow(
            id: 10,
            pid: 800,
            app: "Some App",
            title: "Private Floating Panel",
            bounds: CGRect(x: 10, y: 10, width: 800, height: 500)
        )
        let included = makeWindow(
            id: 11,
            pid: 801,
            app: "Some App",
            title: "Main Document",
            bounds: CGRect(x: 10, y: 10, width: 800, height: 500)
        )

        XCTAssertFalse(manager.shouldKeepWindow(excluded))
        XCTAssertTrue(manager.shouldKeepWindow(included))
    }

    private func makeWindow(
        id: Int,
        pid: pid_t,
        app: String,
        title: String,
        bounds: CGRect,
        isOnScreen: Bool = true,
        bundleID: String? = nil
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            ownerPID: pid,
            ownerName: app,
            ownerBundleID: bundleID ?? "test.\(app.lowercased())",
            title: title,
            layer: 0,
            isOnScreen: isOnScreen,
            alpha: 1.0,
            bounds: bounds
        )
    }
}
