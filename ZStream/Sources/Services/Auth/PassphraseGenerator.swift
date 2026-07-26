//
//  PassphraseGenerator.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

enum PassphraseGenerator {
    private static let words: [String] = {
        guard
            let url = Bundle.main.url(forResource: "bip39_english", withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("bip39_english.txt missing — copy it into Resources/ from the Android app's assets")
            return []
        }
        return contents.split(separator: "\n").map(String.init)
    }()

    static func generate(wordCount: Int = 12) -> [String] {
        guard !words.isEmpty else { return [] }
        return (0..<wordCount).map { _ in
            words[Int.random(in: 0..<words.count, using: &SecureRandomGenerator.shared)]
        }
    }
}

/// Backed by SecRandomCopyBytes — Int.random(in:) alone uses a
/// non-cryptographic generator, which isn't appropriate for anything
/// that doubles as a password.
struct SecureRandomGenerator: RandomNumberGenerator {
    static var shared = SecureRandomGenerator()

    mutating func next() -> UInt64 {
        var value: UInt64 = 0
        _ = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt64>.size, &value)
        return value
    }
}
