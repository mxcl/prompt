import Foundation

/// Unified search result types produced by providers and re-ranked by the conductor.
enum SearchResult {
    case installedAppMetadata(name: String, path: String?, bundleID: String?, description: String?, cask: CaskData.CaskItem?)
    case availableCask(CaskData.CaskItem)
    case historyCommand(command: String, display: String?, subtitle: String?, context: CommandHistoryEntry.Context?, isRecent: Bool)
    case url(URL)
    case filesystemEntry(FileSystemEntry)

    var displayName: String {
        switch self {
        case .installedAppMetadata(let name, _, _, _, _): return name
        case .availableCask(let c): return c.displayName
        case .historyCommand(let command, let display, _, _, _): return display ?? command
        case .url(let url): return url.absoluteString
        case .filesystemEntry(let entry): return entry.displayName
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
        case .installedAppMetadata(_, let path, let bundleID, _, _):
            if let bundleID = bundleID, !bundleID.isEmpty { return bundleID.lowercased() }
            if let path = path, !path.isEmpty { return path.lowercased() }
            return displayName.lowercased()
        case .availableCask(let cask):
            return cask.displayName.lowercased()
        case .historyCommand(let command, _, _, _, _):
            return command.lowercased()
        case .url(let url):
            return url.absoluteString.lowercased()
        case .filesystemEntry(let entry):
            return entry.url.path.lowercased()
        }
    }
}

struct FileSystemEntry {
    let url: URL
    let isDirectory: Bool

    var displayName: String {
        var name = url.lastPathComponent
        if name.isEmpty {
            name = url.path
        }
        if isDirectory && !name.hasSuffix("/") {
            return name + "/"
        }
        return name
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

extension SearchResult {
    var matchedCask: CaskData.CaskItem? {
        switch self {
        case .installedAppMetadata(_, _, _, _, let cask):
            return cask
        case .availableCask(let cask):
            return cask
        case .historyCommand:
            return historyContextResult?.matchedCask
        default:
            return nil
        }
    }
}

extension SearchResult {
    var historyContextResult: SearchResult? {
        guard case .historyCommand(_, _, _, let context, _) = self else { return nil }
        return context?.resolvedSearchResult()
    }
}

extension CommandHistoryEntry.Context {
    func resolvedSearchResult() -> SearchResult? {
        switch self {
        case .availableCask(let token):
            guard let cask = CaskStore.shared.lookup(byNameOrToken: token) else { return nil }
            return .availableCask(cask)
        case .installedApp(let name, let path, let bundleID, let description, let caskToken):
            let cask: CaskData.CaskItem?
            if let token = caskToken {
                cask = CaskStore.shared.lookup(byNameOrToken: token)
            } else {
                cask = nil
            }
            return .installedAppMetadata(name: name, path: path, bundleID: bundleID, description: description, cask: cask)
        }
    }
}
