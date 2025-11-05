import Foundation

struct CommandHistoryEntry: Codable {
    let command: String
    let display: String?
    let subtitle: String?
    private let targetURLString: String?
    private let legacyContext: LegacyContext?

    init(command: String, display: String?, subtitle: String?, targetURL: URL?) {
        self.command = command
        self.display = display
        self.subtitle = subtitle
        self.targetURLString = targetURL?.absoluteString
        self.legacyContext = nil
    }

    var storedURL: URL? {
        if let targetURLString, let url = URL(string: targetURLString) {
            return url
        }
        return legacyContext?.urlRepresentation
    }

    var needsLegacyMigration: Bool {
        return targetURLString == nil && legacyContext != nil
    }

    func updatingTargetURL(_ url: URL?) -> CommandHistoryEntry {
        return CommandHistoryEntry(
            command: command,
            display: display,
            subtitle: subtitle,
            targetURL: url
        )
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case display
        case subtitle
        case targetURLString
        case context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        display = try container.decodeIfPresent(String.self, forKey: .display)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        targetURLString = try container.decodeIfPresent(String.self, forKey: .targetURLString)
        legacyContext = try container.decodeIfPresent(LegacyContext.self, forKey: .context)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(display, forKey: .display)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(targetURLString, forKey: .targetURLString)
    }

    private enum LegacyContext: Codable {
        case availableCask(token: String)
        case installedApp(name: String, path: String?, bundleID: String?, description: String?, caskToken: String?)

        private enum CodingKeys: String, CodingKey {
            case type
            case token
            case name
            case path
            case bundleID
            case description
            case caskToken
        }

        private enum ContextType: String, Codable {
            case availableCask
            case installedApp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(ContextType.self, forKey: .type)
            switch type {
            case .availableCask:
                let token = try container.decode(String.self, forKey: .token)
                self = .availableCask(token: token)
            case .installedApp:
                let name = try container.decode(String.self, forKey: .name)
                let path = try container.decodeIfPresent(String.self, forKey: .path)
                let bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
                let description = try container.decodeIfPresent(String.self, forKey: .description)
                let caskToken = try container.decodeIfPresent(String.self, forKey: .caskToken)
                self = .installedApp(name: name, path: path, bundleID: bundleID, description: description, caskToken: caskToken)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .availableCask(let token):
                try container.encode(ContextType.availableCask, forKey: .type)
                try container.encode(token, forKey: .token)
            case .installedApp(let name, let path, let bundleID, let description, let caskToken):
                try container.encode(ContextType.installedApp, forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encodeIfPresent(path, forKey: .path)
                try container.encodeIfPresent(bundleID, forKey: .bundleID)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encodeIfPresent(caskToken, forKey: .caskToken)
            }
        }

        var urlRepresentation: URL? {
            switch self {
            case .availableCask(let token):
                var components = URLComponents()
                components.scheme = "https"
                components.host = "formulae.brew.sh"
                let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
                components.path = "/cask/\(encoded)"
                return components.url
            case .installedApp(_, let path, _, _, _):
                guard let path else { return nil }
                return URL(fileURLWithPath: path)
            }
        }
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
            migrateLegacyEntriesIfNeeded()
        } else if let legacy = defaults.stringArray(forKey: legacyKey) {
            entries = legacy.map { CommandHistoryEntry(command: $0, display: nil, subtitle: nil, targetURL: nil) }
            persist()
        } else {
            entries = []
        }
    }

    /// Records a command the user launched successfully.
    func record(command: String, display: String?, subtitle: String?, targetURL: URL?) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }
        let trimmedDisplay = CommandHistory.sanitized(display)
        let trimmedSubtitle = CommandHistory.sanitized(subtitle)
        let normalizedURL = targetURL.flatMap { normalizeHistoryURL($0) }

        if let existingIndex = entries.firstIndex(where: { $0.command.caseInsensitiveCompare(trimmedCommand) == .orderedSame }) {
            entries.remove(at: existingIndex)
        }
        entries.insert(
            CommandHistoryEntry(
                command: trimmedCommand,
                display: trimmedDisplay,
                subtitle: trimmedSubtitle,
                targetURL: normalizedURL
            ),
            at: 0
        )

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

    /// Returns the most recent entries regardless of query, limited by the provided count.
    func recentEntries(limit: Int) -> [CommandHistoryEntry] {
        guard limit > 0 else { return [] }
        if entries.count <= limit { return entries }
        return Array(entries.prefix(limit))
    }

    /// Returns stored entries matching the prefix, preserving recency.
    func prefixMatches(for prefix: String, limit: Int = 10) -> [CommandHistoryEntry] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var matches: [CommandHistoryEntry] = []
        for entry in entries {
            if entry.command.lowercased().hasPrefix(lower) {
                matches.append(entry)
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

    /// Removes a stored command from history.
    @discardableResult
    func remove(command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let index = entries.firstIndex(where: {
            $0.command.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            return false
        }
        entries.remove(at: index)
        persist()
        return true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func sanitized(_ text: String?) -> String? {
        guard let text = text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
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
            score += max(8 - gap, 1)
            searchIndex = candidateLower.index(after: matchIndex)
        }

        return 100 + score
    }

    private func migrateLegacyEntriesIfNeeded() {
        var migrated = false
        entries = entries.map { entry in
            guard entry.needsLegacyMigration, let url = entry.storedURL else {
                return entry
            }
            migrated = true
            return entry.updatingTargetURL(url)
        }
        if migrated {
            persist()
        }
    }

    private func normalizeHistoryURL(_ url: URL) -> URL {
        if url.isFileURL {
            return URL(fileURLWithPath: url.path)
        }
        return url
    }
}
