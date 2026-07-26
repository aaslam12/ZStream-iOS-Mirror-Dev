//
//  CacheEnvelope.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Represents any cached value
struct CacheEnvelope<T: Codable>: Codable {
    let value: T
    let cachedAt: Date

    func isStale(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(cachedAt) > ttl
    }
}
