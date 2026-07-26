//
//  BookmarksRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Cache backed loader for user bookmarks. Reads from the Celeste backend when
/// signed in, falling back to the on-disk cache when offline or signed out.
struct BookmarksRepository: CacheBackedLoader {
    let cache: DiskCache = .shared
    let cacheKey = "bookmarks"
    // Always attempt a fresh fetch so server-side bookmarks show up; the
    // CacheBackedLoader falls back to the cached copy if the request fails.
    let ttl: TimeInterval = 0

    func fetchFromNetwork() async throws -> [Bookmark] {
        // Signed out: THROW rather than returning [] — load() writes a successful
        // fetch straight over the cache, so an empty "success" here would wipe
        // every locally-saved bookmark on the next read. Throwing makes load()
        // fall back to the cached copy instead.
        guard let creds = CelesteSession.credentials else { throw URLError(.userAuthenticationRequired) }
        let responses = try await fetchJSON(
            [BookmarkResponse].self,
            from: DefaultEndpoints.bookmarks(userId: creds.userId),
            auth: .bearer(creds.token)
        )
        return responses.compactMap { $0.toBookmark() }
    }

    func add(_ bookmark: Bookmark) async {
        var current = (await cache.read([Bookmark].self, key: cacheKey))?.value ?? []
        if !current.contains(where: { $0.id == bookmark.id && $0.mediaType == bookmark.mediaType }) {
            current.append(bookmark)
            await cache.write(current, key: cacheKey)
        }
        await syncAdd(bookmark)
    }

    func remove(id: Int, mediaType: MediaType) async {
        var current = (await cache.read([Bookmark].self, key: cacheKey))?.value ?? []
        current.removeAll { $0.id == id && $0.mediaType == mediaType }
        await cache.write(current, key: cacheKey)
        await syncRemove(id: id)
    }

    // MARK: - Best-effort server sync

    private func syncAdd(_ bookmark: Bookmark) async {
        guard let creds = CelesteSession.credentials else { return }
        let tmdbId = String(bookmark.id)
        let body = BookmarkInput(
            tmdbId: tmdbId,
            meta: .init(type: bookmark.mediaType == .tv ? "show" : "movie", tmdbId: tmdbId)
        )
        _ = try? await sendJSON(
            method: "POST",
            to: DefaultEndpoints.bookmark(userId: creds.userId, tmdbId: tmdbId),
            body: body,
            auth: .bearer(creds.token)
        )
    }

    private func syncRemove(id: Int) async {
        guard let creds = CelesteSession.credentials else { return }
        _ = try? await sendRequest(
            method: "DELETE",
            to: DefaultEndpoints.bookmark(userId: creds.userId, tmdbId: String(id)),
            auth: .bearer(creds.token)
        )
    }
}
