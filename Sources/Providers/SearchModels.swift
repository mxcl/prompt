import Foundation

/// Unified search result types produced by providers and re-ranked by the conductor.
enum SearchResult {
    case installedAppMetadata(name: String, path: String?, bundleID: String?, description: String?, cask: CaskData.CaskItem?)
    case availableCask(CaskData.CaskItem)
    case historyCommand(command: String, display: String?, subtitle: String?, storedURL: URL?, isRecent: Bool)
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
    private let preferredDisplayPath: String?

    init(url: URL, isDirectory: Bool, preferredDisplayPath: String? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.preferredDisplayPath = preferredDisplayPath
    }

    var displayName: String {
        if let preferred = preferredDisplayPath, !preferred.isEmpty {
            return preferred
        }
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
        guard case .historyCommand(_, _, _, let storedURL, _) = self,
              let url = storedURL else { return nil }
        return SearchResult.historyResult(forHistoryURL: url)
    }

    static func historyResult(forHistoryURL url: URL) -> SearchResult? {
        if let cask = caskFromHistoryURL(url) {
            return .availableCask(cask)
        }
        if url.isFileURL {
            return historyResultForFileURL(url)
        }
        if isWebURL(url) {
            return .url(url)
        }
        return nil
    }

    var installedAppPath: String? {
        switch self {
        case .installedAppMetadata(_, let path, _, _, _):
            return path
        case .historyCommand:
            return historyContextResult?.installedAppPath
        default:
            return nil
        }
    }

    var directoryEntryForNavigation: FileSystemEntry? {
        switch self {
        case .filesystemEntry(let entry) where entry.isDirectory:
            return entry
        case .historyCommand:
            if case .filesystemEntry(let entry) = historyContextResult, entry.isDirectory {
                return entry
            }
            return nil
        default:
            return nil
        }
    }

    private static func caskFromHistoryURL(_ url: URL) -> CaskData.CaskItem? {
        guard let host = url.host?.lowercased(), host == "formulae.brew.sh" else { return nil }
        let components = url.path.split(separator: "/")
        guard components.count >= 2 else { return nil }
        guard components[0].lowercased() == "cask" else { return nil }
        let tokenComponent = components[1]
        let decodedToken = tokenComponent.removingPercentEncoding ?? String(tokenComponent)
        return CaskStore.shared.lookup(byNameOrToken: decodedToken)
    }

    private static func historyResultForFileURL(_ url: URL) -> SearchResult? {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        if url.pathExtension.lowercased() == "app" {
            if let installedApp = installedAppResult(for: url) {
                return installedApp
            }
        }
        let displayPath = abbreviatedHistoryPath(url.path)
        let entry = FileSystemEntry(url: url, isDirectory: isDirectory.boolValue, preferredDisplayPath: displayPath)
        return .filesystemEntry(entry)
    }

    private static func installedAppResult(for url: URL) -> SearchResult? {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let bundle = Bundle(url: url)
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = installedAppDisplayName(bundle: bundle, fallbackName: fallbackName)
        let bundleID = bundle?.bundleIdentifier
        let bundleDescription = installedAppDescription(bundle: bundle)
        let cask = caskForAppURL(url)
        let finalDescription = bundleDescription ?? cask?.desc
        return .installedAppMetadata(
            name: name,
            path: url.path,
            bundleID: bundleID,
            description: finalDescription,
            cask: cask
        )
    }

    private static func installedAppDisplayName(bundle: Bundle?, fallbackName: String) -> String {
        if let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }
        if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }
        return fallbackName
    }

    private static func installedAppDescription(bundle: Bundle?) -> String? {
        if let infoString = bundle?.object(forInfoDictionaryKey: "CFBundleGetInfoString") as? String,
           !infoString.isEmpty {
            return infoString
        }
        if let shortVersion = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !shortVersion.isEmpty,
           let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return "\(name) \(shortVersion)"
        }
        return nil
    }

    private static func caskForAppURL(_ url: URL) -> CaskData.CaskItem? {
        let filename = url.lastPathComponent
        if let match = CaskStore.shared.lookupByAppFilename(filename) {
            return match
        }
        let basename = (filename as NSString).deletingPathExtension
        return CaskStore.shared.lookup(byNameOrToken: basename)
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func abbreviatedHistoryPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homePath.isEmpty else { return path }
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath) {
            let suffix = path.dropFirst(homePath.count)
            if suffix.isEmpty {
                return "~"
            }
            if suffix.first == "/" {
                return "~" + suffix
            }
            return "~/" + suffix
        }
        return path
    }
}
