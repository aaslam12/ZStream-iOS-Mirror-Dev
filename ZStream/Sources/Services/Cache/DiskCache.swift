//
//  DiskCache.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Actor to read and write json CacheEnvelopes to disk with safe concurrent access
actor DiskCache {
    static let shared = DiskCache()

    private let fileManager = FileManager.default
    private let directory: URL

    init(directoryName: String = "ZStreamCache") {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(directoryName)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read<T: Codable>(_ type: T.Type, key: String) -> CacheEnvelope<T>? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheEnvelope<T>.self, from: data)
    }

    func write<T: Codable>(_ value: T, key: String) {
        let envelope = CacheEnvelope(value: value, cachedAt: Date())
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safeKey).json")
    }
}
