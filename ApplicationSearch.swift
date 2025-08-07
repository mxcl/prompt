import Foundation

// Calculate relevance score for sorting results
func calculateRelevanceScore(name: String, query: String) -> Int {
    // Exact match gets highest score
    if name == query {
        return 1000
    }

    // Prefix match gets very high score
    if name.hasPrefix(query) {
        return 900
    }

    // Contains exact query gets high score
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

            // Sort results by relevance: exact match, then prefix match, then others
            let sortedResults = items.sorted { item1, item2 in
                guard let name1 = item1.value(forAttribute: kMDItemDisplayName as String) as? String,
                      let name2 = item2.value(forAttribute: kMDItemDisplayName as String) as? String else {
                    return false
                }

                let lowercaseName1 = name1.lowercased()
                let lowercaseName2 = name2.lowercased()
                let lowercaseQuery = queryString.lowercased()

                // Calculate scores for sorting
                let score1 = calculateRelevanceScore(name: lowercaseName1, query: lowercaseQuery)
                let score2 = calculateRelevanceScore(name: lowercaseName2, query: lowercaseQuery)

                if score1 != score2 {
                    return score1 > score2 // Higher score first
                }

                // If scores are equal, sort alphabetically
                return name1 < name2
            }

            callback(sortedResults)
            query.enableUpdates()
        }

        query.start()
    }
}
