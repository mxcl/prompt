import Foundation

protocol SearchProvider: AnyObject {
    var source: SearchSource { get }
    func search(query: SearchQuery, generation: UInt64, completion: @escaping ([ProviderResult]) -> Void)
}
