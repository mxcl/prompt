import Foundation

final class SearchConductor {
    static let shared = SearchConductor()

    private let providers: [SearchProvider]
    private let aggregationQueue = DispatchQueue(label: "search.conductor.aggregate", qos: .userInitiated)
    private var searchGeneration: UInt64 = 0
    private let generationLock = NSLock()
    private let emptyQueryHistoryLimit = 8
#if DEBUG
    private var debugScoresByIdentifier: [String: Int] = [:]
    private let debugScoresLock = NSLock()
#endif

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
            let recents = CommandHistory.shared
                .recentEntries(limit: emptyQueryHistoryLimit)
                .map { entry in
                    SearchResult.historyCommand(
                        command: entry.command,
                        display: entry.display,
                        subtitle: entry.subtitle,
                        context: entry.context,
                        isRecent: true
                    )
                }
#if DEBUG
            debugScoresLock.lock()
            debugScoresByIdentifier.removeAll()
            debugScoresLock.unlock()
#endif
            completion(recents)
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
        var installedIndexByDisplay: [String: Int] = [:]
        var casks: [ProviderResult] = []
        var history: [ProviderResult] = []
        installed.reserveCapacity(results.count)
        casks.reserveCapacity(results.count)
        history.reserveCapacity(results.count)

        for result in results {
            switch result.result {
            case .installedAppMetadata(_, let path, _, _):
                if let path {
                    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                    installedFilenames.insert(filename)
                }
                installedIndexByDisplay[result.result.displayName.lowercased()] = installed.count
                installed.append(result)
            case .availableCask:
                casks.append(result)
            case .historyCommand:
                history.append(result)
            case .url, .filesystemEntry:
                continue
            }
        }

        let filteredCasks = casks.filter { entry in
            guard case .availableCask(let cask) = entry.result else { return true }
            let duplicatesInstalled = cask.appNames.contains { appName in
                installedFilenames.contains(appName.lowercased())
            }
            return !duplicatesInstalled
        }

        var mergedHistory: [ProviderResult] = []
        mergedHistory.reserveCapacity(history.count)

        for entry in history {
            guard case .historyCommand(_, let display, _, _, _) = entry.result else {
                mergedHistory.append(entry)
                continue
            }
            if let display, !display.isEmpty {
                let key = display.lowercased()
                if let idx = installedIndexByDisplay[key] {
                    let existing = installed[idx]
                    let combinedScore = existing.score + entry.score
                    installed[idx] = ProviderResult(source: existing.source, result: existing.result, score: combinedScore)
                    continue
                }
            }
            mergedHistory.append(entry)
        }

        var filtered: [ProviderResult] = []
        filtered.reserveCapacity(installed.count + mergedHistory.count + filteredCasks.count)
        filtered.append(contentsOf: installed)
        filtered.append(contentsOf: mergedHistory)
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
#if DEBUG
        var debugScores: [String: Int] = [:]
#endif

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
#if DEBUG
            debugScores[identifier] = entry.score
#endif
        }

#if DEBUG
        debugScoresLock.lock()
        debugScoresByIdentifier = debugScores
        debugScoresLock.unlock()
#endif

        return finalResults
    }

    private func priority(for result: ProviderResult, query: SearchQuery) -> Int {
        switch result.result {
        case .installedAppMetadata(let name, _, _, _):
            if name.lowercased() == query.lowercased {
                return 5
            }
            return 3
        case .historyCommand(let command, _, _, _, _):
            if command.lowercased() == query.lowercased {
                return 4
            }
            return 3
        case .availableCask(let cask):
            if isExactMatch(cask: cask, query: query.lowercased) {
                return 3
            }
            return 1
        case .url, .filesystemEntry:
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

#if DEBUG
    func score(for result: SearchResult) -> Int? {
        let identifier = result.identifierHash
        debugScoresLock.lock()
        defer { debugScoresLock.unlock() }
        return debugScoresByIdentifier[identifier]
    }
#endif
}
