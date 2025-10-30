import Foundation

/// Unified search result types produced by providers and re-ranked by the conductor.
enum SearchResult {
    case installedAppMetadata(name: String, path: String?, bundleID: String?, description: String?)
    case availableCask(CaskData.CaskItem)
    case historyCommand(command: String, display: String?)

    var displayName: String {
        switch self {
        case .installedAppMetadata(let name, _, _, _): return name
        case .availableCask(let c): return c.displayName
        case .historyCommand(let command, let display): return display ?? command
        }
    }

    var isInstalled: Bool {
        if case .installedAppMetadata = self { return true }
        return false
    }

    var isHistory: Bool {
        if case .historyCommand = self { return true }
        return false
    }

    var identifierHash: String {
        switch self {
        case .installedAppMetadata(_, let path, let bundleID, _):
            if let bundleID = bundleID, !bundleID.isEmpty { return bundleID.lowercased() }
            if let path = path, !path.isEmpty { return path.lowercased() }
            return displayName.lowercased()
        case .availableCask(let cask):
            return cask.displayName.lowercased()
        case .historyCommand(let command, _):
            return command.lowercased()
        }
    }
}

/// High-level source identifiers so the conductor can reason about cross-source ranking.
enum SearchSource {
    case installedApplications
    case availableCasks
    case commandHistory
}

/// Immutable view of the user query shared with providers.
struct SearchQuery {
    let raw: String
    let trimmed: String
    let lowercased: String

    init(raw: String) {
        self.raw = raw
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trimmed = trimmed
        self.lowercased = trimmed.lowercased()
    }

    var isEmpty: Bool { trimmed.isEmpty }
}

/// Provider-scored result prior to conductor re-ranking.
struct ProviderResult {
    let source: SearchSource
    let result: SearchResult
    let score: Int
}
