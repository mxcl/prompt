import Foundation

let query = NSMetadataQuery()
let q = OperationQueue()
var observer: Any?

func searchApplications(queryString: String, callback: @escaping ([NSMetadataItem]) -> Void) {
    let predicate = NSPredicate(format: "kMDItemKind == 'Application' && kMDItemDisplayName CONTAINS[cd] %@", queryString)
    query.predicate = predicate
    
    query.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]

    if observer == nil {
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
                    continue
                }
                results.append(item)
            }

            callback(results)
            query.enableUpdates()
        }

        query.start()
    }
}
