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
        private let artifacts: [ArtifactContainer]?

        // Helper structure to decode artifacts
        private struct ArtifactContainer: Decodable {
            let app: [String]?

            // Custom decoder to only extract app artifacts and ignore other types
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
            case token, full_token, name, desc, homepage, url, version, sha256, artifacts
        }

        // Computed property to get the main app name for searching
        var displayName: String {
            return name.first ?? token
        }

        // Get all searchable terms (name, token, description)
        var searchableTerms: [String] {
            var terms = name
            terms.append(token)
            terms.append(full_token)
            if let desc = desc {
                terms.append(desc)
            }
            return terms
        }

        // Get app names from artifacts for deduplication
        var appNames: [String] {
            return artifacts?.compactMap { $0.app }.flatMap { $0 } ?? []
        }
    }
}

class CaskProvider {
    static let shared = CaskProvider()

    private let casks: [CaskData.CaskItem]
    private var nameIndex: [String: CaskData.CaskItem] = [:]  // displayName(lowercased) -> item
    private var tokenIndex: [String: CaskData.CaskItem] = [:] // token -> item
    private var appNameIndex: [String: CaskData.CaskItem] = [:] // "AppName.app" lowercased -> item

    private init() {
        guard let path = Bundle.main.path(forResource: "cask", ofType: "json") else {
            casks = []
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            casks = []
            return
        }

        guard let caskData = try? JSONDecoder().decode(CaskData.self, from: data) else {
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

    func searchCasks(query: String) -> [CaskData.CaskItem] {
        let lowercaseQuery = query.lowercased()

        let results = casks.filter { cask in
            // Check if any searchable term contains the query
            return cask.searchableTerms.contains { term in
                term.lowercased().contains(lowercaseQuery)
            }
        }.sorted { cask1, cask2 in
            // Sort by relevance - exact matches first, then prefix matches
            let score1 = calculateCaskRelevanceScore(cask: cask1, query: lowercaseQuery)
            let score2 = calculateCaskRelevanceScore(cask: cask2, query: lowercaseQuery)

            if score1 != score2 {
                return score1 > score2
            }
            return cask1.displayName < cask2.displayName
        }

        return results
    }

    private func calculateCaskRelevanceScore(cask: CaskData.CaskItem, query: String) -> Int {
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

    // Lookup by various identifiers for description augmentation
    func lookup(byNameOrToken raw: String) -> CaskData.CaskItem? {
        let key = raw.lowercased()
        if let c = nameIndex[key] { return c }
        if let c = tokenIndex[key] { return c }
        return nil
    }

    // Lookup by .app bundle filename (case-insensitive)
    func lookupByAppFilename(_ filename: String) -> CaskData.CaskItem? {
        return appNameIndex[filename.lowercased()]
    }
}
