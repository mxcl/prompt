import Foundation

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

let query = NSMetadataQuery()
let q = OperationQueue()
var observer: Any?

func searchApplications(queryString: String, callback: @escaping ([NSMetadataItem]) -> Void) {

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

            // Pre-calculate scores for efficient sorting
            let lowercaseQuery = currentQueryString.lowercased()
            let itemsWithScores = items.map { item -> (item: NSMetadataItem, score: Int, name: String) in
                let name = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
                let lowercaseName = name.lowercased()
                let score = calculateRelevanceScore(name: lowercaseName, query: lowercaseQuery)
                return (item: item, score: score, name: name)
            }

            // Sort using pre-calculated scores
            let sortedResults = itemsWithScores.sorted { item1, item2 in
                if item1.score != item2.score {
                    return item1.score > item2.score // Higher score first
                }
                // If scores are equal, sort alphabetically
                return item1.name < item2.name
            }.map { $0.item }

            callback(sortedResults)
            query.enableUpdates()
        }

        query.start()
    }
}
