import Foundation

// Unified search result type
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

// Helper function to extract query string from wildcard pattern
func getCurrentQueryString(from predicate: NSPredicate?) -> String {
    guard let predicate = predicate else { return "" }
    let predicateString = predicate.predicateFormat
    // Extract the pattern from: kMDItemDisplayName LIKE[cd] "*w*a*r*p*"
    if let range = predicateString.range(of: "\"*") {
        let start = predicateString.index(range.upperBound, offsetBy: 0)
        if let endRange = predicateString.range(of: "*\"", range: start..<predicateString.endIndex) {
            let wildcardPattern = String(predicateString[start..<endRange.lowerBound])
            // Convert "*w*a*r*p*" back to "warp"
            return wildcardPattern.replacingOccurrences(of: "*", with: "")
        }
    }
    return ""
}

// Calculate relevance score for sorting results
func calculateRelevanceScore(name: String, query: String) -> Int {
    // Fast exact match check first
    if name == query {
        return 1000
    }

    // Fast prefix check
    if name.hasPrefix(query) {
        return 900
    }

    // Word-level check so matches like “Visual Studio Code” score well for “code”
    let tokens = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    if tokens.contains(query) {
        return 950
    }
    if tokens.contains(where: { $0.hasPrefix(query) }) {
        return 880
    }

    // Only do more expensive contains check if needed
    if name.contains(query) {
        return 800
    }

    // Wildcard match gets lower score (this is what our LIKE query finds)
    return 100
}

// Calculate relevance score for casks
func calculateCaskRelevanceScore(cask: CaskData.CaskItem, query: String) -> Int {
    let displayName = cask.displayName.lowercased()
    let token = cask.token.lowercased()

    // Exact match on display name or token gets highest score
    if displayName == query || token == query {
        return 1000
    }

    // Prefix match on display name or token
    if displayName.hasPrefix(query) || token.hasPrefix(query) {
        return 900
    }

    // Contains in display name or token
    if displayName.contains(query) || token.contains(query) {
        return 800
    }

    // Check other name variants
    for name in cask.name {
        let lowercaseName = name.lowercased()
        if lowercaseName == query {
            return 950
        }
        if lowercaseName.hasPrefix(query) {
            return 850
        }
        if lowercaseName.contains(query) {
            return 750
        }
    }

    // Match in description gets lower score
    if let desc = cask.desc, desc.lowercased().contains(query) {
        return 500
    }

    return 100
}

// Edit distance <=1 quick check (ASCII oriented)
private func isEditDistanceLeOne(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    let la = a.count, lb = b.count
    if abs(la - lb) > 1 { return false }
    let ac = Array(a), bc = Array(b)
    var i = 0, j = 0, diffs = 0
    while i < la && j < lb {
        if ac[i] == bc[j] { i += 1; j += 1; continue }
        diffs += 1
        if diffs > 1 { return false }
        if la == lb { i += 1; j += 1 } else if la > lb { i += 1 } else { j += 1 }
    }
    if i < la || j < lb { diffs += 1 }
    return diffs <= 1
}

private func normalizedPathForSystemCheck(_ lower: String) -> String {
    let dataPrefix = "/system/volumes/data"
    if lower.hasPrefix(dataPrefix) {
        var remainder = lower.dropFirst(dataPrefix.count)
        if remainder.isEmpty { return "/" }
        if remainder.first != "/" { return "/" + String(remainder) }
        return String(remainder)
    }
    return lower
}

private func isSystemOrEmbedded(path: String) -> Bool {
    let lower = path.lowercased()
    let normalized = normalizedPathForSystemCheck(lower)

    if normalized.hasPrefix("/system/applications/") { return true }
    if normalized.hasPrefix("/system/library/") { return true }
    if normalized.hasPrefix("/system/") && !normalized.hasPrefix("/system/volumes/") { return true }
    if normalized.hasPrefix("/library/") { return true }

    // User Library (~/Library)
    let homeLibPrefixLower = normalizedPathForSystemCheck((NSHomeDirectory() + "/Library/").lowercased())
    if normalized.hasPrefix(homeLibPrefixLower) { return true }

    // Embedded .app detection
    let comps = normalized.split(separator: "/")
    if comps.count > 1 {
        for idx in 0..<(comps.count - 1) {
            if comps[idx].hasSuffix(".app") { return true }
        }
    }
    return false
}

private func shouldIncludeInstalled(path: String?, score: Int, nameLower: String, queryLower: String) -> Bool {
    guard let p = path else { return true }
    if !isSystemOrEmbedded(path: p) { return true }
    // Stricter criteria for system/embedded apps:
    // 1. Exact match always allowed
    if score >= 1000 { return true }
    // 2. Require a sufficiently long prefix (eg ≥5 chars) to show a prefix match
    let minPrefixLen = 5
    if nameLower.hasPrefix(queryLower) && queryLower.count >= minPrefixLen { return true }
    // 3. Allow near‑exact (edit distance ≤1) only if query length also ≥ minPrefixLen
    if queryLower.count >= minPrefixLen && isEditDistanceLeOne(nameLower, queryLower) { return true }
    return false
}

private struct AppHit {
    let name: String        // original display name
    let lower: String       // cached lowercase
    let path: String?
    let bundleID: String?
    let description: String?
}

private let spotlightQueue = OperationQueue()  // for NSMetadataQuery callbacks
private let scoreQueue = DispatchQueue(label: "search.score.queue", qos: .utility)
private var searchGeneration: UInt64 = 0
private let generationLock = NSLock()

func nextGeneration() -> UInt64 {
    generationLock.lock()
    defer { generationLock.unlock() }
    searchGeneration &+= 1
    return searchGeneration
}

private let caskQueue = DispatchQueue(label: "search.cask.queue", qos: .utility)
private var pendingCaskResults: [UInt64: [(cask: CaskData.CaskItem, score: Int)]] = [:]
private let pendingCaskLock = NSLock()

// ...existing code...

func searchApplications(queryString raw: String,
                        callback: @escaping ([SearchResult]) -> Void)
{
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        callback([])
        return
    }

    if trimmed.count == 1 {
        // Optional heuristic for single char; left as-is
    }

    let gen = nextGeneration()
    let qLower = trimmed.lowercased()
    let historyMatches = CommandHistory.shared.fuzzyMatches(for: trimmed, limit: 8)

    // DispatchGroup so we can “wait for both” (Spotlight + cask search) before combining
    let group = DispatchGroup()

    // Kick off cask search in parallel
    group.enter()
    caskQueue.async {
        let matches = CaskProvider.shared.searchCasks(query: qLower)
        var scored: [(cask: CaskData.CaskItem, score: Int)] = []
        scored.reserveCapacity(matches.count)
        for c in matches {
            let s = calculateCaskRelevanceScore(cask: c, query: qLower)
            if s > 0 {
                scored.append((c, s))
            }
        }
        pendingCaskLock.lock()
        pendingCaskResults[gen] = scored
        pendingCaskLock.unlock()
        group.leave()
    }

    // Build wildcard subsequence pattern
    let wildcard = "*" + qLower.map { String($0) }.joined(separator: "*") + "*"

    // Fresh query each time
    let mdq = NSMetadataQuery()
    mdq.operationQueue = spotlightQueue
    mdq.searchScopes = [NSMetadataQueryUserHomeScope,
                        NSMetadataQueryLocalComputerScope]
    mdq.predicate = NSPredicate(
        format: "kMDItemKind == 'Application' AND kMDItemDisplayName LIKE[cd] %@",
        wildcard
    )
    mdq.notificationBatchingInterval = 0

    var obs: NSObjectProtocol?
    obs = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering,
        object: mdq,
        queue: nil) { _ in

            mdq.disableUpdates()
            mdq.stop()
            if let o = obs { NotificationCenter.default.removeObserver(o) }

            // Copy minimal Spotlight results
            let rawResults = (mdq.results as? [NSMetadataItem]) ?? []
            let limit = 300
            var hits: [AppHit] = []
            hits.reserveCapacity(min(rawResults.count, limit))
            for item in rawResults.prefix(limit) {
                guard let name = item.value(forAttribute: kMDItemDisplayName as String) as? String else { continue }
                let path = item.value(forAttribute: kMDItemPath as String) as? String
                let bundleID = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String
                let desc = item.value(forAttribute: kMDItemDescription as String) as? String
                hits.append(AppHit(name: name, lower: name.lowercased(), path: path, bundleID: bundleID, description: desc))
            }

            // Now move to scoring queue; wait for cask search to finish
            scoreQueue.async {
                // Abort if generation stale
                generationLock.lock()
                let currentGen = searchGeneration
                generationLock.unlock()
                guard gen == currentGen else { return }

                // Wait for cask parallel work
                group.wait()

                // Fetch cask results
                pendingCaskLock.lock()
                let caskScored = pendingCaskResults.removeValue(forKey: gen) ?? []
                pendingCaskLock.unlock()

                var combined: [(SearchResult, Int)] = []
                combined.reserveCapacity(hits.count + caskScored.count)

                // Installed apps: filter system/embedded unless strongly relevant; track filenames for dedupe
                var installedFilenames = Set<String>()  // lowercased bundle filenames
                var existingDisplayNames = Set<String>() // lowercased display names for dedupe
                for h in hits {
                    let s = calculateRelevanceScore(name: h.lower, query: qLower)
                    guard s > 0, shouldIncludeInstalled(path: h.path, score: s, nameLower: h.lower, queryLower: qLower) else { continue }
                    if let path = h.path {
                        installedFilenames.insert(URL(fileURLWithPath: path).lastPathComponent.lowercased())
                    }
                    var desc = h.description
                    if (desc == nil || desc?.isEmpty == true) {
                        if let match = CaskProvider.shared.lookup(byNameOrToken: h.name), let cDesc = match.desc, !cDesc.isEmpty {
                            desc = cDesc
                        }
                    }
                    combined.append((.installedAppMetadata(name: h.name,
                                                           path: h.path,
                                                           bundleID: h.bundleID,
                                                           description: desc), s))
                    existingDisplayNames.insert(h.lower)
                }

                // Casks: skip if any declared app filename already installed
                for (c, s) in caskScored {
                    var skip = false
                    for appName in c.appNames { // Eg: "Visual Studio Code.app"
                        if installedFilenames.contains(appName.lowercased()) { skip = true; break }
                    }
                    if skip { continue }
                    combined.append((.availableCask(c), s))
                    existingDisplayNames.insert(c.displayName.lowercased())
                    existingDisplayNames.insert(c.token.lowercased())
                }

                let historyBaseScore = 200
                var addedHistory = Set<String>()
                for match in historyMatches {
                    let command = match.entry.command
                    let display = match.entry.display
                    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedCommand.isEmpty else { continue }
                    let lower = trimmedCommand.lowercased()
                    if existingDisplayNames.contains(lower) { continue }
                    if addedHistory.contains(lower) { continue }
                    addedHistory.insert(lower)
                    let rawScore = historyBaseScore + match.score
                    let boundedScore = min(rawScore, 700) // keep history below solid app matches
                    combined.append((.historyCommand(command: trimmedCommand, display: display), boundedScore))
                }

                // Sort primarily by score, preferring installed, then history when scores tie
                let sorted = combined.sorted {
                    if $0.1 != $1.1 { return $0.1 > $1.1 }

                    let aInstalled = $0.0.isInstalled
                    let bInstalled = $1.0.isInstalled
                    if aInstalled != bInstalled { return aInstalled && !bInstalled }

                    let aHistory = $0.0.isHistory
                    let bHistory = $1.0.isHistory
                    if aHistory != bHistory { return aHistory && !bHistory }

                    return $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending
                }

                var seenIdentifiers = Set<String>()
                var deduped: [SearchResult] = []
                deduped.reserveCapacity(sorted.count)
                for (result, _) in sorted {
                    let id = result.identifierHash
                    if seenIdentifiers.contains(id) { continue }
                    seenIdentifiers.insert(id)
                    deduped.append(result)
                }

                // Final gen check
                generationLock.lock()
                let stillCurrent = (gen == searchGeneration)
                generationLock.unlock()
                guard stillCurrent else { return }

                DispatchQueue.main.async {
                    callback(deduped)
                }
            }
        }

    mdq.start()
}
