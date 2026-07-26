//
//  StringSimilarity.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

enum StringSimilarity {
    
    private static let stopwords: Set<String> = ["the", "a", "an", "and", "of", "collection"]

    /// Returns 0...1+ — exact/prefix/substring matches score highest,
    /// near-misses (typos) still score meaningfully via edit distance.
    static func textScore(title: String, query: String) -> Double {
        let t = title.lowercased().trimmingCharacters(in: .whitespaces)
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }

        if t == q { return 1.0 }
        if t.hasPrefix(q) { return 0.95 }
        if t.contains(q) { return 0.85 }
        return similarity(t, q) * 0.8
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        let distance = levenshteinDistance(a, b)
        return max(0, 1.0 - Double(distance) / Double(maxLen))
    }

    /// Standard edit-distance DP — counts insertions/deletions/substitutions
    /// needed to turn one string into the other. Lower = more similar.
    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previousRow = Array(0...bChars.count)
        var currentRow = [Int](repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            currentRow[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,
                    currentRow[j - 1] + 1,
                    previousRow[j - 1] + cost
                )
            }
            previousRow = currentRow
        }
        return previousRow[bChars.count]
    }
    
    static func tokens(_ text: String) -> [String] {
        let cleaned = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
        return cleaned.split(separator: " ").map(String.init).filter { !stopwords.contains($0) }
    }

    /// Fraction of the query's meaningful words found in the title — exact
    /// or within 1 edit (typo tolerance) per word. This is what lets "fast
    /// and furious" match "The Fast and the Furious Collection": extra
    /// words and reordering don't break it, unlike whole-string comparison.
    static func tokenOverlapScore(title: String, query: String) -> Double {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return 0 }
        let titleTokens = Set(tokens(title))

        let matched = queryTokens.filter { q in
            titleTokens.contains(q) || titleTokens.contains { fuzzyMatch($0, q) }
        }.count

        return Double(matched) / Double(queryTokens.count)
    }

    private static func fuzzyMatch(_ a: String, _ b: String) -> Bool {
        guard abs(a.count - b.count) <= 2 else { return false }
        return levenshteinDistance(a, b) <= 1
    }
    
    /// Exponential decay by age — recent releases score near 1.0, very old
    /// ones decay toward a floor rather than hitting zero (so a genuinely
    /// old classic someone searches for by exact title can still surface).
    static func recencyScore(releaseYear: Int?, halfLifeYears: Double = 15, floor: Double = 0.15) -> Double {
        guard let releaseYear else { return 0.5 }
        let currentYear = Calendar.current.component(.year, from: Date())
        let age = max(0, Double(currentYear - releaseYear))
        let decayed = pow(0.5, age / halfLifeYears)
        return max(floor, decayed)
    }
}
