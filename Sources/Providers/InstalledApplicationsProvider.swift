import Foundation

private struct AppHit {
    let name: String
    let lower: String
    let path: String?
    let bundleID: String?
    let description: String?
}

final class InstalledApplicationsProvider: SearchProvider {
    let source: SearchSource = .installedApplications

    private static let metadataQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "search.spotlight.queue"
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private let scoringQueue = DispatchQueue(label: "search.installed.score.queue", qos: .userInitiated)
    private let metadataLimit = 300

    func search(query: SearchQuery, generation: UInt64, completion: @escaping ([ProviderResult]) -> Void) {
        guard !query.isEmpty else {
            completion([])
            return
        }

        let wildcard = FuzzySearchHelper.wildcardPattern(for: query.lowercased)
        let metadataQuery = NSMetadataQuery()
        metadataQuery.operationQueue = Self.metadataQueue
        metadataQuery.searchScopes = [
            NSMetadataQueryUserHomeScope,
            NSMetadataQueryLocalComputerScope
        ]
        metadataQuery.predicate = NSPredicate(
            format: "kMDItemKind == 'Application' AND kMDItemDisplayName LIKE[cd] %@",
            wildcard
        )
        metadataQuery.notificationBatchingInterval = 0

        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: nil) { [weak self] _ in
                guard let self else { return }
                metadataQuery.disableUpdates()
                metadataQuery.stop()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }

                let rawResults = (metadataQuery.results as? [NSMetadataItem]) ?? []
                let hits = rawResults.prefix(self.metadataLimit).compactMap { item -> AppHit? in
                    guard let name = item.value(forAttribute: kMDItemDisplayName as String) as? String else {
                        return nil
                    }
                    let path = item.value(forAttribute: kMDItemPath as String) as? String
                    let bundleID = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String
                    let desc = item.value(forAttribute: kMDItemDescription as String) as? String
                    return AppHit(name: name, lower: name.lowercased(), path: path, bundleID: bundleID, description: desc)
                }

                self.scoringQueue.async {
                    let lowerQuery = query.lowercased
                    let scored = self.scoreAndFilter(hits: hits, lowercasedQuery: lowerQuery)
                    completion(scored)
                }
            }

        metadataQuery.start()
    }

    private func scoreAndFilter(hits: [AppHit], lowercasedQuery query: String) -> [ProviderResult] {
        var results: [ProviderResult] = []
        results.reserveCapacity(hits.count)

        for hit in hits {
            let score = Self.relevanceScore(nameLower: hit.lower, query: query)
            guard score > 0 else { continue }
            guard Self.shouldIncludeInstalled(path: hit.path, score: score, nameLower: hit.lower, queryLower: query) else { continue }

            let matchedCask = matchCask(for: hit)

            var description = hit.description
            if (description == nil || description?.isEmpty == true),
               let cDesc = matchedCask?.desc,
               !cDesc.isEmpty {
                description = cDesc
            }

            let result = SearchResult.installedAppMetadata(
                name: hit.name,
                path: hit.path,
                bundleID: hit.bundleID,
                description: description,
                cask: matchedCask
            )
            results.append(ProviderResult(source: .installedApplications, result: result, score: score))
        }

        return results
    }

    private static func relevanceScore(nameLower: String, query: String) -> Int {
        if nameLower == query { return 1000 }
        if nameLower.hasPrefix(query) { return 900 }

        let tokens = FuzzySearchHelper.tokens(in: nameLower)
        if tokens.contains(query) { return 950 }
        if tokens.contains(where: { $0.hasPrefix(query) }) { return 880 }

        if nameLower.contains(query) { return 800 }
        return 100
    }

    private static func shouldIncludeInstalled(path: String?, score: Int, nameLower: String, queryLower: String) -> Bool {
        guard let path else { return true }
        if !isSystemOrEmbedded(path: path) { return true }
        if score >= 1000 { return true }
        let minPrefixLen = 5
        if nameLower.hasPrefix(queryLower) && queryLower.count >= minPrefixLen { return true }
        if queryLower.count >= minPrefixLen && FuzzySearchHelper.isEditDistanceLeOne(nameLower, queryLower) {
            return true
        }
        return false
    }

    private static func isSystemOrEmbedded(path: String) -> Bool {
        let lower = path.lowercased()
        let normalized = normalizedPathForSystemCheck(lower)

        if normalized.hasPrefix("/system/applications/") { return true }
        if normalized.hasPrefix("/system/library/") { return true }
        if normalized.hasPrefix("/system/") && !normalized.hasPrefix("/system/volumes/") { return true }
        if normalized.hasPrefix("/library/") { return true }

        let homeLibrary = normalizedPathForSystemCheck((NSHomeDirectory() + "/Library/").lowercased())
        if normalized.hasPrefix(homeLibrary) { return true }

        let components = normalized.split(separator: "/")
        if components.count > 1 {
            for idx in 0..<(components.count - 1) {
                if components[idx].hasSuffix(".app") {
                    return true
                }
            }
        }
        return false
    }

    private static func normalizedPathForSystemCheck(_ lower: String) -> String {
        let dataPrefix = "/system/volumes/data"
        if lower.hasPrefix(dataPrefix) {
            var remainder = lower.dropFirst(dataPrefix.count)
            if remainder.isEmpty { return "/" }
            if remainder.first != "/" { return "/" + String(remainder) }
            return String(remainder)
        }
        return lower
    }

    private func matchCask(for hit: AppHit) -> CaskData.CaskItem? {
        if let c = CaskStore.shared.lookup(byNameOrToken: hit.name) {
            return c
        }

        guard let path = hit.path else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        if let c = CaskStore.shared.lookupByAppFilename(filename) {
            return c
        }
        let basename = (filename as NSString).deletingPathExtension
        return CaskStore.shared.lookup(byNameOrToken: basename)
    }
}
