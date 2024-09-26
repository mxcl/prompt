import CoreSpotlight
import SwiftUI

struct ContentView: View {
    @State private var searchText = ""
    @ObservedObject private var apps = ObservableArray()

    var body: some View {
        VStack {
            TextField("Run", text: $searchText)
                .onChange(of: searchText, perform: xquery)
            
            List(apps.array) { item in
                Text(item.value(forAttribute: kMDItemDisplayName as String) as! String)
            }
        }
        .padding()
    }
    
    func xquery(input: String) {
        searchApplications(queryString: input) { results in
            DispatchQueue.main.async {
                apps.array = results
            }
        }
    }
}

extension NSMetadataItem: Identifiable {
    public var id: ObjectIdentifier {
        // ObjectIdentifier(value(forAttribute: kMDItemCFBundleIdentifier as String) as! NSString)
        // ^^ confusingly doesn't work
        return ObjectIdentifier(self)
    }
}

class ObservableArray: ObservableObject {
    @Published var array: [NSMetadataItem] = []
}

#Preview {
    ContentView()
}

let query = NSMetadataQuery()
let q = OperationQueue()
var observer: Any?

func searchApplications(queryString: String, callback: @escaping ([NSMetadataItem]) -> Void)
{
    let predicate = NSPredicate(format: "kMDItemKind == 'Application' && (kMDItemDisplayName BEGINSWITH[cd] %@ || kMDItemDisplayName CONTAINS[cd] %@)", queryString, " \(queryString)")

    query.predicate = predicate

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
