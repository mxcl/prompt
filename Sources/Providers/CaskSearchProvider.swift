import Foundation

// Updated structure to match actual cask.json format
struct CaskData: Decodable {
    let data: [CaskItem]

    struct CaskItem: Decodable {
        let token: String
        let full_token: String
        let name: [String]
        let desc: String?
        let homepage: String?
        let url: String?
        let version: String?
        let sha256: String?
        let deprecated: Bool?
        private let artifacts: [ArtifactContainer]?

        struct ArtifactContainer: Decodable {
            let app: [String]?

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let dict = try? container.decode([String: [String]].self),
                   let appArray = dict["app"] {
                    self.app = appArray
                } else {
                    self.app = nil
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case token
            case full_token
            case name
            case desc
            case homepage
            case url
            case version
            case sha256
            case deprecated
            case artifacts
        }

        var displayName: String {
            return name.first ?? token
        }

        var searchableTerms: [String] {
            var terms = name
            terms.append(token)
            terms.append(full_token)
            if let desc = desc { terms.append(desc) }
            return terms
        }

        var appNames: [String] {
            return artifacts?.compactMap { $0.app }.flatMap { $0 } ?? []
        }

        var isDeprecated: Bool {
            return deprecated == true
        }
    }
}

final class CaskStore {
    static let shared = CaskStore()

    let casks: [CaskData.CaskItem]
    private var nameIndex: [String: CaskData.CaskItem] = [:]
    private var tokenIndex: [String: CaskData.CaskItem] = [:]
    private var appNameIndex: [String: CaskData.CaskItem] = [:]

    private init() {
        guard let path = Bundle.main.path(forResource: "cask", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let caskData = try? JSONDecoder().decode(CaskData.self, from: data) else {
            casks = []
            return
        }

        casks = caskData.data
        for c in casks {
            tokenIndex[c.token.lowercased()] = c
            nameIndex[c.displayName.lowercased()] = c
            for n in c.name { nameIndex[n.lowercased()] = c }
            for appName in c.appNames { appNameIndex[appName.lowercased()] = c }
        }
    }

    func lookup(byNameOrToken raw: String) -> CaskData.CaskItem? {
        let key = raw.lowercased()
        if let c = nameIndex[key] { return c }
        if let c = tokenIndex[key] { return c }
        return nil
    }

    func lookupByAppFilename(_ filename: String) -> CaskData.CaskItem? {
        return appNameIndex[filename.lowercased()]
    }
}

final class CaskSearchProvider: SearchProvider {
    let source: SearchSource = .availableCasks

    private let queue = DispatchQueue(label: "search.cask.queue", qos: .userInitiated)

    func search(query: SearchQuery, generation: UInt64, completion: @escaping ([ProviderResult]) -> Void) {
        guard !query.isEmpty else {
            completion([])
            return
        }

        let lower = query.lowercased

        queue.async {
            let matches = CaskStore.shared.casks.compactMap { cask -> ProviderResult? in
                guard CaskSearchProvider.matches(cask: cask, lowercasedQuery: lower) else { return nil }
                let baseScore = CaskSearchProvider.relevanceScore(for: cask, lowercasedQuery: lower)
                let adjustedScore = CaskSearchProvider.adjustedScore(for: cask, baseScore: baseScore)
                guard adjustedScore > 0 else { return nil }
                return ProviderResult(source: .availableCasks, result: .availableCask(cask), score: adjustedScore)
            }
            completion(matches)
        }
    }

    private static func matches(cask: CaskData.CaskItem, lowercasedQuery: String) -> Bool {
        return cask.searchableTerms.contains { term in
            term.lowercased().contains(lowercasedQuery)
        }
    }

    private static func relevanceScore(for cask: CaskData.CaskItem, lowercasedQuery query: String) -> Int {
        let displayName = cask.displayName.lowercased()
        let token = cask.token.lowercased()

        if displayName == query || token == query {
            return 1000
        }

        if displayName.hasPrefix(query) || token.hasPrefix(query) {
            return 900
        }

        if displayName.contains(query) || token.contains(query) {
            return 800
        }

        for name in cask.name {
            let lowercaseName = name.lowercased()
            if lowercaseName == query { return 950 }
            if lowercaseName.hasPrefix(query) { return 850 }
            if lowercaseName.contains(query) { return 750 }
        }

        if let desc = cask.desc, desc.lowercased().contains(query) {
            return 500
        }

        return 100
    }

    private static func adjustedScore(for cask: CaskData.CaskItem, baseScore: Int) -> Int {
        guard cask.isDeprecated else { return baseScore }
        let penalty = 200
        return max(baseScore - penalty, 0)
    }
}
