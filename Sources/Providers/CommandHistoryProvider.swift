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

        var matches = history.prefixMatches(for: query.trimmed, limit: limit)
        if matches.isEmpty {
            matches = history.recentEntries(limit: limit)
        }
        let loweredQuery = query.lowercased
        var added = Set<String>()
        var results: [ProviderResult] = []
        results.reserveCapacity(matches.count)

        for (index, entry) in matches.enumerated() {
            let command = entry.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { continue }
            let lower = command.lowercased()
            if added.contains(lower) { continue }
            added.insert(lower)

            var score = baseScore + max(0, (limit - index) * 10)
            if lower == loweredQuery {
                score = 700
            }
            let result = SearchResult.historyCommand(command: command, display: entry.display)
            results.append(ProviderResult(source: .commandHistory, result: result, score: score))
        }

        completion(results)
    }
}
