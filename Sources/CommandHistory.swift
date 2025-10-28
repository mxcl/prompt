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
}
