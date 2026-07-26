//
//  LastUsedSourceStore.swift
//  ZStream
//
//  Remembers which source last worked for a given title, so
//  AppSettings.prioritizeLastUsedSource can put it first on the next watch
//  regardless of the user's configured source order.
//

import Foundation
import ZStreamCore

actor LastUsedSourceStore {
    static let shared = LastUsedSourceStore()

    private let cacheKey = "last_used_sources"
    private var dictionary: [String: String]?

    /// Groups movie/show playback under one key (ignoring season/episode) —
    /// which source works is a property of the title, not the episode.
    static func mediaKey(for media: MediaRequest) -> String {
        switch media.type {
        case .movie: return "movie-\(media.tmdbId)"
        case .show: return "show-\(media.tmdbId)"
        }
    }

    func sourceId(for mediaKey: String) async -> String? {
        await loaded()[mediaKey]
    }

    func record(sourceId: String, for mediaKey: String) async {
        var current = await loaded()
        current[mediaKey] = sourceId
        dictionary = current
        await DiskCache.shared.write(current, key: cacheKey)
    }

    private func loaded() async -> [String: String] {
        if let dictionary { return dictionary }
        let value = (await DiskCache.shared.read([String: String].self, key: cacheKey))?.value ?? [:]
        dictionary = value
        return value
    }
}
