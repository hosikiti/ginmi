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

    private func makeWindow(id: Int, pid: pid_t, app: String, title: String, bounds: CGRect, isOnScreen: Bool = true) -> WindowInfo {
        WindowInfo(
            id: id,
            ownerPID: pid,
            ownerName: app,
            ownerBundleID: "test.\(app.lowercased())",
            title: title,
            layer: 0,
            isOnScreen: isOnScreen,
            alpha: 1.0,
            bounds: bounds
        )
    }
}
