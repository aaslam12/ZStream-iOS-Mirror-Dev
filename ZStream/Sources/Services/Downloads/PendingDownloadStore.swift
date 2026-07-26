//
//  PendingDownloadStore.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/24/26.
//

import Foundation

/// Everything needed to rebuild an `ActiveDownload` for a task we didn't
/// create this launch — e.g. one still running in the background
/// `AVAssetDownloadURLSession` after the app was force-quit and relaunched.
struct PendingDownloadMeta: Codable {
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let episodeInfo: EpisodeInfo?
    /// The asset's on-disk location, once willDownloadTo: reports it. Nil
    /// until then. Persisted (not just kept in memory) because willDownloadTo:
    /// fires exactly once per task, early in its life — if the app relaunches
    /// after that but before the task finishes, nothing will fire it again,
    /// so a reconnected task that completes post-relaunch needs this to know
    /// where to actually find the finished file.
    var assetLocationPath: String? = nil
}

/// A plain, synchronous JSON file — deliberately NOT the actor-based
/// `DiskCache` used elsewhere. `DownloadManager.init` needs this data
/// available before it hands off to `AVAssetDownloadURLSession`, because any
/// download that finished or failed while the app wasn't running replays its
/// delegate callbacks the moment the session is recreated with the same
/// identifier — and those callbacks look up this metadata to know what to
/// commit. An `await` here would risk losing that race.
enum PendingDownloadStore {
    private static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("pending_downloads.json")
    }()

    static func loadAll() -> [String: PendingDownloadMeta] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: PendingDownloadMeta].self, from: data)
        else { return [:] }
        return decoded
    }

    static func save(id: String, meta: PendingDownloadMeta) {
        var all = loadAll()
        all[id] = meta
        write(all)
    }

    static func remove(id: String) {
        var all = loadAll()
        guard all.removeValue(forKey: id) != nil else { return }
        write(all)
    }

    static func updateAssetLocation(id: String, path: String) {
        var all = loadAll()
        guard var meta = all[id] else { return }
        meta.assetLocationPath = path
        all[id] = meta
        write(all)
    }

    private static func write(_ all: [String: PendingDownloadMeta]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
