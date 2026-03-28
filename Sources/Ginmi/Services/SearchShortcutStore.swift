import Foundation

final class SearchShortcutStore {
    private enum Keys {
        static let shortcuts = "searchShortcuts"
        static let usageCount = "windowUsageCount"
        static let lastUsed = "windowLastUsed"
    }

    private let defaults: UserDefaults
    private var shortcutsCache: [String: String]
    private var usageCountCache: [String: Int]
    private var lastUsedCache: [String: TimeInterval]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shortcutsCache = defaults.dictionary(forKey: Keys.shortcuts) as? [String: String] ?? [:]
        self.usageCountCache = defaults.dictionary(forKey: Keys.usageCount) as? [String: Int] ?? [:]
        self.lastUsedCache = defaults.dictionary(forKey: Keys.lastUsed) as? [String: TimeInterval] ?? [:]
    }

    func preferredWindowID(for query: String) -> String? {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return nil }
        return shortcutsCache[normalized]
    }

    func remember(query: String, windowIdentifier: String) {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return }
        shortcutsCache[normalized] = windowIdentifier
        defaults.set(shortcutsCache, forKey: Keys.shortcuts)
    }

    func incrementUsage(for windowIdentifier: String) {
        usageCountCache[windowIdentifier, default: 0] += 1
        defaults.set(usageCountCache, forKey: Keys.usageCount)

        touchRecency(for: windowIdentifier)
    }

    func touchRecency(for windowIdentifier: String, at date: Date = Date()) {
        lastUsedCache[windowIdentifier] = date.timeIntervalSince1970
        defaults.set(lastUsedCache, forKey: Keys.lastUsed)
    }

    func usageCount(for windowIdentifier: String) -> Int {
        return usageCountCache[windowIdentifier, default: 0]
    }

    func lastUsed(for windowIdentifier: String) -> TimeInterval {
        return lastUsedCache[windowIdentifier, default: 0]
    }

    func resetShortcuts() {
        shortcutsCache.removeAll()
        usageCountCache.removeAll()
        lastUsedCache.removeAll()
        defaults.removeObject(forKey: Keys.shortcuts)
        defaults.removeObject(forKey: Keys.usageCount)
        defaults.removeObject(forKey: Keys.lastUsed)
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
