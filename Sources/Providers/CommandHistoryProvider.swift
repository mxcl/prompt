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

        let matches = history.fuzzyMatches(for: query.trimmed, limit: limit)
        var added = Set<String>()
        var results: [ProviderResult] = []
        results.reserveCapacity(matches.count)

        for match in matches {
            let command = match.entry.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { continue }
            let lower = command.lowercased()
            if added.contains(lower) { continue }
            added.insert(lower)

            let rawScore = baseScore + match.score
            let bounded = min(rawScore, 700)
            let result = SearchResult.historyCommand(command: command, display: match.entry.display)
            results.append(ProviderResult(source: .commandHistory, result: result, score: bounded))
        }

        completion(results)
    }
}
