import Foundation

let query = NSMetadataQuery()
let q = OperationQueue()
var observer: Any?

func searchApplications(queryString: String, callback: @escaping ([NSMetadataItem]) -> Void) {
    print("searchApplications called with: '\(queryString)'")

    let predicate = NSPredicate(format: "kMDItemKind == 'Application' && kMDItemDisplayName CONTAINS[cd] %@", queryString)
    print("Using predicate: \(predicate)")

    query.predicate = predicate
    
    // Set search scopes explicitly
    query.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]

    if observer == nil {
        print("Setting up metadata query observer")
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: q)
        { notification in

            guard let query = notification.object as? NSMetadataQuery else { return }

            query.disableUpdates()

            print("NSMetadataQuery found \(query.resultCount) items")
            for (index, item) in (query.results as! [NSMetadataItem]).enumerated() {
                if index < 5 { // Show first 5 for debugging
                    let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? "nil"
                    let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "nil"
                    let kind = item.value(forAttribute: kMDItemKind as String) as? String ?? "nil"
                    print("  Item \(index): \(displayName) at \(path) kind: \(kind)")
                }
            }

            var results: [NSMetadataItem] = []
            var ids = Set<String>()
            for item in query.results as! [NSMetadataItem] {
                guard item.value(forAttribute: kMDItemDisplayName as String) is String, let id = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String else {
                    continue
                }
                guard ids.insert(id).inserted else {
                    for key in item.attributes {
                        print(key, item.value(forAttribute: key) ?? "nil")
                    }
                    continue
                }
                results.append(item)
            }

            callback(results)

            query.enableUpdates()
//
//            NotificationCenter.default.removeObserver(observer!)
//            observer = nil
        }

        query.start()
    }
}

func debugSearchGmail() {
    print("=== DEBUG: Searching for Gmail without kMDItemKind filter ===")
    
    let debugQuery = NSMetadataQuery()
    let predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", "gmail")
    debugQuery.predicate = predicate
    
    var debugObserver: Any?
    debugObserver = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering,
        object: debugQuery,
        queue: q
    ) { notification in
        
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        
        print("DEBUG: Found \(query.resultCount) items matching 'gmail'")
        
        for (index, item) in (query.results as! [NSMetadataItem]).enumerated() {
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? "nil"
            let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "nil"
            let kind = item.value(forAttribute: kMDItemKind as String) as? String ?? "nil"
            let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? "nil"
            let bundleId = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String ?? "nil"
            
            print("DEBUG Item \(index):")
            print("  Display Name: \(displayName)")
            print("  Path: \(path)")
            print("  Kind: \(kind)")
            print("  Content Type: \(contentType)")
            print("  Bundle ID: \(bundleId)")
            print("  ---")
        }
        
        if let observer = debugObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        debugQuery.stop()
    }
    
    debugQuery.start()
}

func debugSearchGmailByPath() {
    print("=== DEBUG: Searching for items in Chrome Apps directory ===")
    
    let debugQuery = NSMetadataQuery()
    
    // Try setting search scopes explicitly
    debugQuery.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
    
    let predicate = NSPredicate(format: "kMDItemPath LIKE '*Chrome Apps*'")
    debugQuery.predicate = predicate
    
    print("DEBUG: Search scopes: \(debugQuery.searchScopes)")
    
    var debugObserver: Any?
    debugObserver = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering,
        object: debugQuery,
        queue: q
    ) { notification in
        
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        
        print("DEBUG: Found \(query.resultCount) items in Chrome Apps directory")
        
        for (index, item) in (query.results as! [NSMetadataItem]).enumerated() {
            let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? "nil"
            let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "nil"
            let kind = item.value(forAttribute: kMDItemKind as String) as? String ?? "nil"
            let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? "nil"
            let bundleId = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String ?? "nil"
            
            print("DEBUG Item \(index):")
            print("  Display Name: \(displayName)")
            print("  Path: \(path)")
            print("  Kind: \(kind)")
            print("  Content Type: \(contentType)")
            print("  Bundle ID: \(bundleId)")
            print("  ---")
        }
        
        if let observer = debugObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        debugQuery.stop()
    }
    
    debugQuery.start()
}
