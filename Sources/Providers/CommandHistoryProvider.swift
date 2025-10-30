import Foundation

final class CommandHistoryProvider: SearchProvider {
    let source: SearchSource = .commandHistory
    private let history = CommandHistory.shared
    private let baseScore = 200
    private let limit = 8

    func search(query: SearchQuery, generation: UInt64, completion: @escaping ([ProviderResult]) -> Void) {
        guard !query.isEmpty else {
            completion([])
            return
        }

        let loweredQuery = query.lowercased
        var candidates: [(entry: CommandHistoryEntry, score: Int)] = []

        let fuzzy = history.fuzzyMatches(for: query.trimmed, limit: limit)
        if !fuzzy.isEmpty {
            for (index, match) in fuzzy.enumerated() {
                let recencyBoost = max(0, (limit - index) * 10)
                let score = baseScore + recencyBoost + match.score
                candidates.append((match.entry, score))
            }
        } else {
            let recents = history.recentEntries(limit: limit)
            for (index, entry) in recents.enumerated() {
                let recencyBoost = max(0, (limit - index) * 10)
                let score = baseScore + recencyBoost
                candidates.append((entry, score))
            }
        }

        var added = Set<String>()
        var results: [ProviderResult] = []
        results.reserveCapacity(candidates.count)

        for candidate in candidates {
            let entry = candidate.entry
            let command = entry.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { continue }
            let lower = command.lowercased()
            if added.contains(lower) { continue }
            added.insert(lower)

            var score = candidate.score
            if lower == loweredQuery {
                score = max(score, 1000)
            }
            let result = SearchResult.historyCommand(command: command, display: entry.display)
            results.append(ProviderResult(source: .commandHistory, result: result, score: score))
        }

        completion(results)
    }
}
