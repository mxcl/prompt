import Foundation

enum FuzzySearchHelper {
    static func wildcardPattern(for query: String) -> String {
        guard !query.isEmpty else { return "*" }
        return "*" + query.map { String($0) }.joined(separator: "*") + "*"
    }

    static func tokens(in string: String) -> [String] {
        return string
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func isEditDistanceLeOne(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let la = a.count, lb = b.count
        if abs(la - lb) > 1 { return false }
        let ac = Array(a), bc = Array(b)
        var i = 0, j = 0, diffs = 0
        while i < la && j < lb {
            if ac[i] == bc[j] {
                i += 1
                j += 1
                continue
            }
            diffs += 1
            if diffs > 1 { return false }
            if la == lb {
                i += 1
                j += 1
            } else if la > lb {
                i += 1
            } else {
                j += 1
            }
        }
        if i < la || j < lb { diffs += 1 }
        return diffs <= 1
    }
}
