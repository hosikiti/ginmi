import AppKit
import Combine
import Foundation

@MainActor
final class SearchPanelViewModel: ObservableObject {
    enum PresentationMode {
        case standard
        case commandTab
    }

    @Published var query = "" {
        didSet {
            if presentationMode == .standard {
                scheduleSearch()
            } else {
                searchDebounceTask?.cancel()
                runCommandTabSearch()
            }
        }
    }
    @Published private(set) var results: [SearchResultItem] = []
    @Published var selectedIndex = 0
    @Published private(set) var isVisible = false

    var onCommitSelection: ((WindowInfo, String) -> Void)?
    var onCancel: (() -> Void)?

    private let windowManager: any WindowManaging
    private let installedAppManager: any InstalledAppManaging
    private let searcher: FuzzySearcher
    private let shortcutsStore: SearchShortcutStore
    private let defaults: UserDefaults
    private var searchDebounceTask: Task<Void, Never>?
    private var allWindows: [WindowInfo] = []
    private var presentationMode: PresentationMode = .standard
    private let debugCommandTab = ProcessInfo.processInfo.environment["GINMI_DEBUG_COMMAND_TAB"] == "1"

    init(
        windowManager: any WindowManaging,
        installedAppManager: any InstalledAppManaging,
        searcher: FuzzySearcher,
        shortcutsStore: SearchShortcutStore,
        defaults: UserDefaults = .standard
    ) {
        self.windowManager = windowManager
        self.installedAppManager = installedAppManager
        self.searcher = searcher
        self.shortcutsStore = shortcutsStore
        self.defaults = defaults
    }

    func show(resetQuery: Bool, mode: PresentationMode, initiallySelectedWindowID: Int? = nil) {
        presentationMode = mode
        isVisible = true
        if resetQuery {
            query = ""
        }
        refreshWindows()
        if presentationMode == .commandTab, let initiallySelectedWindowID {
            prioritizeWindow(withID: initiallySelectedWindowID)
        }
        if presentationMode == .commandTab {
            runCommandTabSearch()
        } else {
            runSearch()
        }
        if let initiallySelectedWindowID {
            selectWindow(withID: initiallySelectedWindowID)
        } else {
            selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
        }
    }

    func hide() {
        isVisible = false
        query = ""
        results = []
        selectedIndex = 0
    }

    func refreshWindows() {
        allWindows = windowManager.fetchAllWindows()
    }

    func moveSelection(delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    func appendQuery(_ text: String) {
        guard !text.isEmpty else { return }
        query.append(text)
        if presentationMode == .commandTab {
            selectedIndex = 0
        }
    }

    func deleteLastQueryCharacter() {
        guard !query.isEmpty else { return }
        query.removeLast()
        if presentationMode == .commandTab {
            selectedIndex = 0
        }
    }

    func hasSelection() -> Bool {
        results.indices.contains(selectedIndex)
    }

    func selectWindow(withID windowID: Int) {
        guard let index = results.firstIndex(where: {
            if case let .window(window) = $0.kind {
                return window.id == windowID
            }
            return false
        }) else {
            selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
            return
        }
        selectedIndex = index
    }

    func commitSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        let selected = results[selectedIndex]

        switch selected.kind {
        case let .window(window):
            _ = windowManager.activate(window: window)
            shortcutsStore.remember(query: query, windowIdentifier: window.identifier)
            shortcutsStore.incrementUsage(for: window.identifier)
            onCommitSelection?(window, query)
        case let .app(app):
            _ = installedAppManager.launch(app: app)
            onCancel?()
        }
    }

    func cancel() {
        onCancel?()
    }

    func icon(for result: SearchResultItem) -> NSImage {
        switch result.kind {
        case let .window(window):
            return windowManager.icon(for: window)
        case let .app(app):
            return installedAppManager.icon(for: app)
        }
    }

    func selectedWindow() -> WindowInfo? {
        guard results.indices.contains(selectedIndex) else { return nil }
        if case let .window(window) = results[selectedIndex].kind {
            return window
        }
        return nil
    }

    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.runSearch()
        }
    }

    private func runSearch() {
        let recencyWeightEnabled = defaults.object(forKey: "recencyWeightEnabled") as? Bool ?? true
        let preferredWindowID = shortcutsStore.preferredWindowID(for: query)
        let rankedWindows = searcher.rank(
            windows: allWindows,
            query: query,
            preferredWindowID: preferredWindowID,
            usageProvider: { [shortcutsStore] in shortcutsStore.usageCount(for: $0) },
            recencyProvider: { [shortcutsStore] in shortcutsStore.lastUsed(for: $0) },
            recencyWeightEnabled: recencyWeightEnabled
        )
        let windowResults = rankedWindows.map { SearchResultItem(kind: .window($0.window), score: $0.score) }
        let appResults = appResults(query: query, strictContains: false)
        results = windowResults + appResults
        selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
    }

    private func runCommandTabSearch() {
        results = rankForCommandTab(query: query)
        selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)

        guard debugCommandTab else { return }
        let titles = results.map {
            switch $0.kind {
            case let .window(window):
                return "id=\(window.id) pid=\(window.ownerPID) \(window.ownerName) :: \(window.displayTitle) bounds=\(window.boundsSignature) emptyTitle=\(window.title.isEmpty)"
            case let .app(app):
                return "app=\(app.name) bundle=\(app.bundleIdentifier) path=\(app.url.path)"
            }
        }
        print("GINMI_COMMAND_TAB query=\"\(query)\" matches=\(titles)")
    }

    private func rankForCommandTab(query: String) -> [SearchResultItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return allWindows.map { SearchResultItem(kind: .window($0), score: 0) }
        }

        let preferredWindowID = shortcutsStore.preferredWindowID(for: query)
        let windowResults = allWindows
            .compactMap { window -> SearchResultItem? in
                let appName = window.ownerName.lowercased()
                let title = window.displayTitle.lowercased()
                let searchable = "\(appName) \(title)"
                guard searchable.contains(normalizedQuery) else { return nil }

                var score = 1.0
                if appName == normalizedQuery {
                    score -= 0.6
                } else if appName.hasPrefix(normalizedQuery) {
                    score -= 0.4
                } else if title.hasPrefix(normalizedQuery) {
                    score -= 0.3
                } else if title.contains(normalizedQuery) {
                    score -= 0.15
                }

                if preferredWindowID == window.identifier {
                    score -= 0.2
                }

                score -= Double(shortcutsStore.usageCount(for: window.identifier)) * 0.01
                return SearchResultItem(kind: .window(window), score: score)
            }
            .sorted { (lhs: SearchResultItem, rhs: SearchResultItem) in
                if lhs.score == rhs.score {
                    return lhs.primaryText.localizedCaseInsensitiveCompare(rhs.primaryText) == .orderedAscending
                }
                return lhs.score < rhs.score
            }
        let appResults = appResults(query: query, strictContains: true)
        return windowResults + appResults
    }

    private func prioritizeWindow(withID windowID: Int) {
        guard let index = allWindows.firstIndex(where: { $0.id == windowID }) else { return }
        let current = allWindows.remove(at: index)
        allWindows.insert(current, at: 0)
    }

    private func appResults(query: String, strictContains: Bool) -> [SearchResultItem] {
        let isFallbackEnabled = defaults.object(forKey: "searchInstalledAppsFallbackEnabled") as? Bool ?? true
        guard isFallbackEnabled else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        return installedAppManager.installedApps()
            .compactMap { app -> SearchResultItem? in
                let searchable = app.name.lowercased()
                let matches: Bool
                if strictContains {
                    matches = searchable.contains(normalizedQuery)
                } else {
                    matches = searchable.contains(normalizedQuery) || isSubsequence(normalizedQuery, in: searchable)
                }
                guard matches else { return nil }

                var score = 1.0
                if searchable == normalizedQuery {
                    score -= 0.6
                } else if searchable.hasPrefix(normalizedQuery) {
                    score -= 0.4
                } else if searchable.contains(normalizedQuery) {
                    score -= 0.2
                }
                return SearchResultItem(kind: .app(app), score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.primaryText.localizedCaseInsensitiveCompare(rhs.primaryText) == .orderedAscending
                }
                return lhs.score < rhs.score
            }
    }

    private func isSubsequence(_ query: String, in text: String) -> Bool {
        if query.isEmpty { return true }
        var textIndex = text.startIndex
        for queryChar in query {
            var found = false
            while textIndex < text.endIndex {
                if text[textIndex] == queryChar {
                    found = true
                    text.formIndex(after: &textIndex)
                    break
                }
                text.formIndex(after: &textIndex)
            }
            if !found {
                return false
            }
        }
        return true
    }
}
