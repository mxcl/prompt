import Foundation

let query = NSMetadataQuery()
let q = OperationQueue()
var observer: Any?

func searchApplications(queryString: String, callback: @escaping ([NSMetadataItem]) -> Void) {
    print("searchApplications called with: '\(queryString)'")

    let predicate = NSPredicate(format: "kMDItemKind == 'Application' && (kMDItemDisplayName BEGINSWITH[cd] %@ || kMDItemDisplayName CONTAINS[cd] %@)", queryString, " \(queryString)")

    query.predicate = predicate

    if observer == nil {
        print("Setting up metadata query observer")
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: q)
        { notification in

            guard let query = notification.object as? NSMetadataQuery else { return }

            query.disableUpdates()

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
