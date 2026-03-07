import Foundation

final class SearchShortcutStore {
    private enum Keys {
        static let shortcuts = "searchShortcuts"
        static let usageCount = "windowUsageCount"
        static let lastUsed = "windowLastUsed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preferredWindowID(for query: String) -> String? {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return nil }
        let map = defaults.dictionary(forKey: Keys.shortcuts) as? [String: String] ?? [:]
        return map[normalized]
    }

    func remember(query: String, windowIdentifier: String) {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return }
        var map = defaults.dictionary(forKey: Keys.shortcuts) as? [String: String] ?? [:]
        map[normalized] = windowIdentifier
        defaults.set(map, forKey: Keys.shortcuts)
    }

    func incrementUsage(for windowIdentifier: String) {
        var usage = defaults.dictionary(forKey: Keys.usageCount) as? [String: Int] ?? [:]
        usage[windowIdentifier, default: 0] += 1
        defaults.set(usage, forKey: Keys.usageCount)

        var recency = defaults.dictionary(forKey: Keys.lastUsed) as? [String: TimeInterval] ?? [:]
        recency[windowIdentifier] = Date().timeIntervalSince1970
        defaults.set(recency, forKey: Keys.lastUsed)
    }

    func usageCount(for windowIdentifier: String) -> Int {
        let usage = defaults.dictionary(forKey: Keys.usageCount) as? [String: Int] ?? [:]
        return usage[windowIdentifier, default: 0]
    }

    func lastUsed(for windowIdentifier: String) -> TimeInterval {
        let recency = defaults.dictionary(forKey: Keys.lastUsed) as? [String: TimeInterval] ?? [:]
        return recency[windowIdentifier, default: 0]
    }

    func resetShortcuts() {
        defaults.removeObject(forKey: Keys.shortcuts)
        defaults.removeObject(forKey: Keys.usageCount)
        defaults.removeObject(forKey: Keys.lastUsed)
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
