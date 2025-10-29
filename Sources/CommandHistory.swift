import Foundation

struct CommandHistoryEntry: Codable {
    let command: String
    let display: String?

    init(command: String, display: String?) {
        self.command = command
        self.display = display
    }
}

struct CommandHistoryMatch {
    let entry: CommandHistoryEntry
    let score: Int
}

/// Persists successful run commands so we can offer completions the user actually used.
final class CommandHistory {
    static let shared = CommandHistory()

    private let storageKey = "CommandHistoryEntries"
    private let legacyKey = "CommandHistoryEntries"
    private let maxEntries = 200
    private var entries: [CommandHistoryEntry]
    private let defaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CommandHistoryEntry].self, from: data) {
            entries = decoded
        } else if let legacy = defaults.stringArray(forKey: legacyKey) {
            entries = legacy.map { CommandHistoryEntry(command: $0, display: nil) }
            persist()
        } else {
            entries = []
        }
    }

    /// Records a command the user launched successfully.
    func record(command: String, display: String?) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }
        let trimmedDisplay = display?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingIndex = entries.firstIndex(where: { $0.command.caseInsensitiveCompare(trimmedCommand) == .orderedSame }) {
            entries.remove(at: existingIndex)
        }
        entries.insert(CommandHistoryEntry(command: trimmedCommand, display: trimmedDisplay), at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        persist()
    }

    /// Returns the first stored command that completes the provided prefix.
    func bestCompletion(for prefix: String) -> String? {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        return entries.first(where: { $0.command.lowercased().hasPrefix(lower) })?.command
    }

    /// Returns stored commands that match the prefix, in recency order.
    func completions(matching prefix: String, limit: Int = 10) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var matches: [String] = []
        for entry in entries {
            if entry.command.lowercased().hasPrefix(lower) {
                matches.append(entry.command)
            }
            if matches.count == limit { break }
        }
        return matches
    }

    /// Returns fuzzy matches scored so higher scores indicate better fit.
    func fuzzyMatches(for query: String, limit: Int = 5) -> [CommandHistoryMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var scored: [(entry: CommandHistoryEntry, score: Int, index: Int)] = []
        for (idx, entry) in entries.enumerated() {
            guard let score = fuzzyScore(candidate: entry.command, query: lower) else { continue }
            scored.append((entry, score, idx))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.index < $1.index
        }
        return Array(scored.prefix(limit)).map { CommandHistoryMatch(entry: $0.entry, score: $0.score) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
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
