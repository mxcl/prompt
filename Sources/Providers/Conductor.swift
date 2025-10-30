import Foundation

final class SearchConductor {
    static let shared = SearchConductor()

    private let providers: [SearchProvider]
    private let aggregationQueue = DispatchQueue(label: "search.conductor.aggregate", qos: .userInitiated)
    private var searchGeneration: UInt64 = 0
    private let generationLock = NSLock()

    private init(providers: [SearchProvider] = [
        InstalledApplicationsProvider(),
        CommandHistoryProvider(),
        CaskSearchProvider()
    ]) {
        self.providers = providers
    }

    func search(query raw: String, completion: @escaping ([SearchResult]) -> Void) {
        let query = SearchQuery(raw: raw)
        if query.isEmpty {
            completion([])
            return
        }

        let generation = nextGeneration()
        let group = DispatchGroup()
        var collected: [ProviderResult] = []
        let resultLock = NSLock()

        for provider in providers {
            group.enter()
            provider.search(query: query, generation: generation) { results in
                resultLock.lock()
                collected.append(contentsOf: results)
                resultLock.unlock()
                group.leave()
            }
        }

        aggregationQueue.async {
            group.wait()
            guard self.isCurrentGeneration(generation) else { return }
            let reranked = self.rerank(results: collected, query: query)
            DispatchQueue.main.async {
                guard self.isCurrentGeneration(generation) else { return }
                completion(reranked)
            }
        }
    }

    private func rerank(results: [ProviderResult], query: SearchQuery) -> [SearchResult] {
        var installedFilenames = Set<String>()
        var installed: [ProviderResult] = []
        var casks: [ProviderResult] = []
        var others: [ProviderResult] = []
        installed.reserveCapacity(results.count)
        casks.reserveCapacity(results.count)
        others.reserveCapacity(results.count)

        for result in results {
            switch result.result {
            case .installedAppMetadata(_, let path, _, _):
                if let path {
                    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                    installedFilenames.insert(filename)
                }
                installed.append(result)
            case .availableCask:
                casks.append(result)
            case .historyCommand:
                others.append(result)
            }
        }

        let filteredCasks = casks.filter { entry in
            guard case .availableCask(let cask) = entry.result else { return true }
            let duplicatesInstalled = cask.appNames.contains { appName in
                installedFilenames.contains(appName.lowercased())
            }
            return !duplicatesInstalled
        }

        var filtered: [ProviderResult] = []
        filtered.reserveCapacity(installed.count + others.count + filteredCasks.count)
        filtered.append(contentsOf: installed)
        filtered.append(contentsOf: others)
        filtered.append(contentsOf: filteredCasks)

        let sorted = filtered.sorted { lhs, rhs in
            let lhsPriority = self.priority(for: lhs, query: query)
            let rhsPriority = self.priority(for: rhs, query: query)
            if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.result.displayName.localizedCaseInsensitiveCompare(rhs.result.displayName) == .orderedAscending
        }

        var seenIdentifiers = Set<String>()
        var seenDisplayNames = Set<String>()
        var finalResults: [SearchResult] = []
        finalResults.reserveCapacity(sorted.count)

        for entry in sorted {
            let identifier = entry.result.identifierHash
            if seenIdentifiers.contains(identifier) { continue }
            seenIdentifiers.insert(identifier)
            let displayKey = entry.result.displayName.lowercased()
            if seenDisplayNames.contains(displayKey) && !entry.result.isHistory {
                continue
            }
            seenDisplayNames.insert(displayKey)
            finalResults.append(entry.result)
        }

        return finalResults
    }

    private func priority(for result: ProviderResult, query: SearchQuery) -> Int {
        switch result.result {
        case .installedAppMetadata:
            return 3
        case .historyCommand(let command, _):
            print("FOO", command.lowercased(), query.lowercased)
            if command.lowercased() == query.lowercased {
                return 4
            }
            return 3
        case .availableCask(let cask):
            if isExactMatch(cask: cask, query: query.lowercased) {
                return 3
            }
            return 1
        }
    }

    private func isExactMatch(cask: CaskData.CaskItem, query: String) -> Bool {
        let lowerName = cask.displayName.lowercased()
        if lowerName == query { return true }
        if cask.token.lowercased() == query { return true }
        if cask.full_token.lowercased() == query { return true }
        return false
    }

    private func nextGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        searchGeneration &+= 1
        return searchGeneration
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == searchGeneration
    }
}
