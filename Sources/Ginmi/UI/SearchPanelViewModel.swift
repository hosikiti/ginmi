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
    @Published private(set) var results: [RankedWindow] = []
    @Published var selectedIndex = 0
    @Published private(set) var isVisible = false

    var onCommitSelection: ((WindowInfo, String) -> Void)?
    var onCancel: (() -> Void)?

    private let windowManager: any WindowManaging
    private let searcher: FuzzySearcher
    private let shortcutsStore: SearchShortcutStore
    private let defaults: UserDefaults
    private var searchDebounceTask: Task<Void, Never>?
    private var allWindows: [WindowInfo] = []
    private var presentationMode: PresentationMode = .standard
    private let debugCommandTab = ProcessInfo.processInfo.environment["GINMI_DEBUG_COMMAND_TAB"] == "1"

    init(
        windowManager: any WindowManaging,
        searcher: FuzzySearcher,
        shortcutsStore: SearchShortcutStore,
        defaults: UserDefaults = .standard
    ) {
        self.windowManager = windowManager
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
    }

    func deleteLastQueryCharacter() {
        guard !query.isEmpty else { return }
        query.removeLast()
    }

    func hasSelection() -> Bool {
        results.indices.contains(selectedIndex)
    }

    func selectWindow(withID windowID: Int) {
        guard let index = results.firstIndex(where: { $0.window.id == windowID }) else {
            selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
            return
        }
        selectedIndex = index
    }

    func commitSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        let selected = results[selectedIndex].window

        _ = windowManager.activate(window: selected)
        shortcutsStore.remember(query: query, windowIdentifier: selected.identifier)
        shortcutsStore.incrementUsage(for: selected.identifier)
        onCommitSelection?(selected, query)
    }

    func cancel() {
        onCancel?()
    }

    func icon(for rankedWindow: RankedWindow) -> NSImage {
        windowManager.icon(for: rankedWindow.window)
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
        results = searcher.rank(
            windows: allWindows,
            query: query,
            preferredWindowID: preferredWindowID,
            usageProvider: { [shortcutsStore] in shortcutsStore.usageCount(for: $0) },
            recencyProvider: { [shortcutsStore] in shortcutsStore.lastUsed(for: $0) },
            recencyWeightEnabled: recencyWeightEnabled
        )
        selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
    }

    private func runCommandTabSearch() {
        results = rankForCommandTab(query: query)
        selectedIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)

        guard debugCommandTab else { return }
        let titles = results.map {
            "id=\($0.window.id) pid=\($0.window.ownerPID) \($0.window.ownerName) :: \($0.window.displayTitle) bounds=\($0.window.boundsSignature) emptyTitle=\($0.window.title.isEmpty)"
        }
        print("GINMI_COMMAND_TAB query=\"\(query)\" matches=\(titles)")
    }

    private func rankForCommandTab(query: String) -> [RankedWindow] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return allWindows.map { RankedWindow(window: $0, score: 0) }
        }

        let preferredWindowID = shortcutsStore.preferredWindowID(for: query)
        return allWindows
            .compactMap { window in
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
                return RankedWindow(window: window, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.window.displayTitle.localizedCaseInsensitiveCompare(rhs.window.displayTitle) == .orderedAscending
                }
                return lhs.score < rhs.score
            }
    }
}
