import Foundation

// Unified search result type
enum SearchResult {
    case installedApp(NSMetadataItem)
    case availableCask(CaskData.CaskItem)

    var displayName: String {
        switch self {
        case .installedApp(let item):
            return item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
        case .availableCask(let cask):
            return cask.displayName
        }
    }

    var isInstalled: Bool {
        switch self {
        case .installedApp:
            return true
        case .availableCask:
            return false
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

let query = NSMetadataQuery()
let q = OperationQueue()
var observer: Any?

func searchApplications(queryString: String, callback: @escaping ([SearchResult]) -> Void) {
    print("Starting search for: '\(queryString)'")

    // Create wildcard pattern: "sfari" becomes "*s*f*a*r*i*"
    let wildcardPattern = "*" + queryString.map { String($0) }.joined(separator: "*") + "*"
    let predicate = NSPredicate(format: "kMDItemKind == 'Application' && kMDItemDisplayName LIKE[cd] %@", wildcardPattern)
    query.predicate = predicate

    query.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]

    if observer == nil {
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: q)
        { notification in
            guard let query = notification.object as? NSMetadataQuery else { return }
            query.disableUpdates()

            // Extract the current query string from the predicate instead of using captured value
            let currentQueryString = getCurrentQueryString(from: query.predicate)

            var items: [NSMetadataItem] = []
            var ids = Set<String>()
            for item in query.results as! [NSMetadataItem] {
                guard item.value(forAttribute: kMDItemDisplayName as String) is String, let id = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String else {
                    continue
                }
                guard ids.insert(id).inserted else {
                    continue
                }
                items.append(item)
            }

            print("Found \(items.count) installed apps for '\(currentQueryString)'")

            // Convert installed apps to SearchResult and calculate scores
            let lowercaseQuery = currentQueryString.lowercased()
            let appResultsWithScores = items.map { item -> (result: SearchResult, score: Int, name: String) in
                let name = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
                let lowercaseName = name.lowercased()
                let score = calculateRelevanceScore(name: lowercaseName, query: lowercaseQuery)
                return (result: .installedApp(item), score: score, name: name)
            }

            // Search casks
            let caskResults = CaskProvider.shared.searchCasks(query: currentQueryString)
                .prefix(20) // Limit cask results to keep performance good

            // Create a set of installed app names for deduplication
            let installedAppNames = Set(items.compactMap { item -> String? in
                guard let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String else { return nil }
                // Get the app name by removing .app extension if present
                return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
            })

            // Filter out casks that have apps already installed
            let filteredCaskResults = caskResults.filter { cask in
                // Check if any of the cask's app artifacts match installed apps
                let caskAppNames = cask.appNames.map { appName in
                    // Remove .app extension from cask app names too
                    appName.hasSuffix(".app") ? String(appName.dropLast(4)) : appName
                }

                // Only include cask if none of its apps are already installed
                return !caskAppNames.contains { installedAppNames.contains($0) }
            }.map { cask -> (result: SearchResult, score: Int, name: String) in
                let score = calculateCaskRelevanceScore(cask: cask, query: lowercaseQuery)
                return (result: .availableCask(cask), score: score, name: cask.displayName)
            }

            print("Found \(filteredCaskResults.count) available casks for '\(currentQueryString)' (after deduplication)")

            // Combine and sort all results
            let allResults = appResultsWithScores + Array(filteredCaskResults)
            let sortedResults = allResults.sorted { item1, item2 in
                // Always prioritize installed apps over uninstalled ones
                if item1.result.isInstalled != item2.result.isInstalled {
                    return item1.result.isInstalled
                }

                // Within the same installation status, sort by score
                if item1.score != item2.score {
                    return item1.score > item2.score // Higher score first
                }
                // If scores are equal, sort alphabetically
                return item1.name < item2.name
            }.map { $0.result }

            callback(sortedResults)
            query.enableUpdates()
        }

        query.start()
    }
}
