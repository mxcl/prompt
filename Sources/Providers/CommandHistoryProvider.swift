import Foundation

final class CommandHistoryProvider: SearchProvider {
    let source: SearchSource = .commandHistory
    private let history = CommandHistory.shared
    private let baseScore = 200
    private let limit = 8
    private let lowRankingPruneWindow = 120 // drop fuzzy matches that trail the leader by more than this delta
    private let deprecatedCaskPenalty = 200

    func search(query: SearchQuery, generation: UInt64, completion: @escaping ([ProviderResult]) -> Void) {
        guard !query.isEmpty else {
            completion([])
            return
        }

        let loweredQuery = query.lowercased
        var candidates: [(entry: CommandHistoryEntry, score: Int, isRecent: Bool)] = []

        let fuzzy = filteredFuzzyMatches(for: query.trimmed)
        for (index, match) in fuzzy.enumerated() {
            let recencyBoost = max(0, (limit - index) * 10)
            let score = baseScore + recencyBoost + match.score
            candidates.append((match.entry, score, false))
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
            if isDeprecatedCask(entry: entry) {
                score = max(score - deprecatedCaskPenalty, 0)
            }
            let result = SearchResult.historyCommand(
                command: command,
                display: entry.display,
                subtitle: entry.subtitle,
                context: entry.context,
                isRecent: candidate.isRecent
            )
            results.append(ProviderResult(source: .commandHistory, result: result, score: score))
        }

        completion(results)
    }

    private func filteredFuzzyMatches(for query: String) -> [CommandHistoryMatch] {
        let matches = history.fuzzyMatches(for: query, limit: limit)
        guard let topScore = matches.first?.score else { return [] }
        let minimumScore = max(topScore - lowRankingPruneWindow, 0)
        return matches.filter { $0.score >= minimumScore }
    }

    private func isDeprecatedCask(entry: CommandHistoryEntry) -> Bool {
        guard let context = entry.context else { return false }
        guard let matchedCask = context.resolvedSearchResult()?.matchedCask else { return false }
        return matchedCask.isDeprecated
    }
}
