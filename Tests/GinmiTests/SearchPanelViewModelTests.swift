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
            searcher: FuzzySearcher(),
            shortcutsStore: store,
            defaults: defaults
        )

        viewModel.show(resetQuery: true, mode: .commandTab)
        XCTAssertEqual(viewModel.results.count, 4)

        viewModel.query = "arc"

        XCTAssertEqual(viewModel.results.map(\.window.ownerName), ["Arc", "Arc"])
        XCTAssertTrue(viewModel.results.allSatisfy { "\($0.window.ownerName) \($0.window.displayTitle)".lowercased().contains("arc") })
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
