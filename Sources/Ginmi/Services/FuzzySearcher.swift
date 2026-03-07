import Foundation
import Fuse

struct RankedWindow: Identifiable {
    let window: WindowInfo
    let score: Double

    var id: Int { window.id }
}

final class FuzzySearcher {
    private let fuse: Fuse

    init() {
        fuse = Fuse(
            location: 0,
            distance: 100,
            threshold: 0.45,
            maxPatternLength: 64,
            isCaseSensitive: false,
            tokenize: true
        )
    }

    func rank(
        windows: [WindowInfo],
        query: String,
        preferredWindowID: String?,
        usageProvider: (String) -> Int,
        recencyProvider: (String) -> TimeInterval,
        recencyWeightEnabled: Bool,
        strictContains: Bool = false
    ) -> [RankedWindow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return windows
                .sorted {
                    let lhs = usageProvider($0.identifier) * 1000 + Int(recencyProvider($0.identifier))
                    let rhs = usageProvider($1.identifier) * 1000 + Int(recencyProvider($1.identifier))
                    return lhs > rhs
                }
                .map { RankedWindow(window: $0, score: 0) }
        }

        var ranked: [RankedWindow] = []
        let normalizedQuery = trimmed.lowercased()

        for window in windows {
            let searchable = window.searchableText.lowercased()
            let hasDirectContains = searchable.contains(normalizedQuery)
            if strictContains {
                guard hasDirectContains else { continue }
            } else {
                let hasSubsequence = isSubsequence(normalizedQuery, in: searchable)
                guard hasDirectContains || hasSubsequence else { continue }
            }

            let searchResult = fuse.search(trimmed, in: window.searchableText)

            var effectiveScore = searchResult?.score ?? 0.4
            if hasDirectContains {
                effectiveScore -= 0.15
            }
            effectiveScore -= acronymBonus(query: trimmed, text: window.searchableText)

            if preferredWindowID == window.identifier {
                effectiveScore -= 0.35
            }

            let usageBoost = Double(usageProvider(window.identifier)) * 0.02
            effectiveScore -= usageBoost

            if recencyWeightEnabled {
                let recencyBoost = recencyProvider(window.identifier) / Date().timeIntervalSince1970
                effectiveScore -= max(0, min(recencyBoost, 1)) * 0.03
            }

            ranked.append(RankedWindow(window: window, score: effectiveScore))
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.window.displayTitle < rhs.window.displayTitle
            }
            return lhs.score < rhs.score
        }
    }

    private func isSubsequence(_ query: String, in text: String) -> Bool {
        if query.isEmpty { return true }
        var textIndex = text.startIndex
        for q in query {
            var found = false
            while textIndex < text.endIndex {
                if text[textIndex] == q {
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

    private func acronymBonus(query: String, text: String) -> Double {
        let queryLower = query.lowercased()
        let words = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        guard !words.isEmpty else { return 0 }

        let acronym = words.compactMap { $0.first }.map(String.init).joined()
        if acronym.hasPrefix(queryLower) {
            return 0.2
        }

        if words.contains(where: { $0.hasPrefix(queryLower) }) {
            return 0.1
        }

        return 0
    }
}
