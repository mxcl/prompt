import Foundation

// Unified search result type
enum SearchResult {
    case installedAppMetadata(name: String, path: String?, bundleID: String?)
    case availableCask(CaskData.CaskItem)

    var displayName: String {
        switch self {
        case .installedAppMetadata(let name, _, _): return name
        case .availableCask(let c): return c.displayName
        }
    }
    var isInstalled: Bool {
        if case .installedAppMetadata = self { return true }
        return false
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

private struct AppHit {
    let name: String        // original display name
    let lower: String       // cached lowercase
    let path: String?
    let bundleID: String?
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
                hits.append(AppHit(name: name, lower: name.lowercased(), path: path, bundleID: bundleID))
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
                
                // Installed apps
                var installedSet = Set<String>()
                installedSet.reserveCapacity(hits.count)
                for h in hits {
                    installedSet.insert(h.lower)
                    let s = calculateRelevanceScore(name: h.lower, query: qLower)
                    if s > 0 {
                        combined.append((.installedAppMetadata(name: h.name,
                                                               path: h.path,
                                                               bundleID: h.bundleID), s))
                    }
                }
                
                // Casks (dedupe by display name)
                for (c, s) in caskScored {
                    let dn = c.displayName.lowercased()
                    if installedSet.contains(dn) { continue }
                    combined.append((.availableCask(c), s))
                }
                
                // Sort (installed first)
                let sorted = combined.sorted {
                    let ai = $0.0.isInstalled
                    let bi = $1.0.isInstalled
                    if ai != bi { return ai && !bi }
                    if $0.1 != $1.1 { return $0.1 > $1.1 }
                    return $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending
                }.map { $0.0 }
                
                // Final gen check
                generationLock.lock()
                let stillCurrent = (gen == searchGeneration)
                generationLock.unlock()
                guard stillCurrent else { return }
                
                DispatchQueue.main.async {
                    callback(sorted)
                }
            }
        }
    
    mdq.start()
}
