//
//  CacheBackedLoader.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Protocol that defines how to access a cache value, on cache-miss (see ext) it will fetch from the network
protocol CacheBackedLoader {
    associatedtype Value: Codable
    var cache: DiskCache { get }
    var cacheKey: String { get }
    var ttl: TimeInterval { get }

    func fetchFromNetwork() async throws -> Value
}

extension CacheBackedLoader {
    func load() async throws -> Value {
        let cached = await cache.read(Value.self, key: cacheKey)

        if let cached, !cached.isStale(ttl: ttl) {
            return cached.value
        }

        do {
            let fresh = try await fetchFromNetwork()
            await cache.write(fresh, key: cacheKey)
            return fresh
        } catch {
            if let cached {
                return cached.value
            }
            throw error
        }
    }
}
