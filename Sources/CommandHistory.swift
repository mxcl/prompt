import Foundation

/// Persists successful run commands so we can offer completions the user actually used.
final class CommandHistory {
    static let shared = CommandHistory()

    private let storageKey = "CommandHistoryEntries"
    private let maxEntries = 200
    private var entries: [String]
    private let defaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        entries = defaults.stringArray(forKey: storageKey) ?? []
    }

    /// Records a command the user launched successfully.
    func record(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existingIndex = entries.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            entries.remove(at: existingIndex)
        }
        entries.insert(trimmed, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        defaults.set(entries, forKey: storageKey)
    }

    /// Returns the first stored command that completes the provided prefix.
    func bestCompletion(for prefix: String) -> String? {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        return entries.first(where: { $0.lowercased().hasPrefix(lower) })
    }

    /// Returns stored commands that match the prefix, in recency order.
    func completions(matching prefix: String, limit: Int = 10) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var matches: [String] = []
        for entry in entries {
            if entry.lowercased().hasPrefix(lower) {
                matches.append(entry)
            }
            if matches.count == limit { break }
        }
        return matches
    }

    /// Returns fuzzy matches scored so higher scores indicate better fit.
    func fuzzyMatches(for query: String, limit: Int = 5) -> [(command: String, score: Int)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var scored: [(command: String, score: Int, index: Int)] = []
        for (idx, entry) in entries.enumerated() {
            guard let score = fuzzyScore(candidate: entry, query: lower) else { continue }
            scored.append((entry, score, idx))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.index < $1.index
        }
        return Array(scored.prefix(limit)).map { ($0.command, $0.score) }
    }

    private func fuzzyScore(candidate: String, query: String) -> Int? {
        let candidateLower = candidate.lowercased()
        if candidateLower == query { return 300 }
        if candidateLower.hasPrefix(query) { return 260 }
        if let range = candidateLower.range(of: query) {
            let startDistance = candidateLower.distance(from: candidateLower.startIndex, to: range.lowerBound)
            let proximityBonus = max(0, 60 - startDistance)
            return 220 + proximityBonus
        }

        var score = 0
        var searchIndex = candidateLower.startIndex
        for qChar in query {
            guard let matchIndex = candidateLower[searchIndex...].firstIndex(of: qChar) else {
                return nil
            }
            let gap = candidateLower.distance(from: searchIndex, to: matchIndex)
            score += max(15 - gap, 1)
            searchIndex = candidateLower.index(after: matchIndex)
        }

        return 120 + score
    }
}
