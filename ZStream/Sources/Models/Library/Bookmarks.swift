//
//  Bookmarks.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// A bookmark added by the user
struct Bookmark: Codable, Identifiable, Equatable {
    let id: Int
    let mediaType: MediaType
    let addedAt: Date
}

// MARK: - Backend shapes

/// The backend's per-item metadata. Only the fields we consume are modeled;
/// everything is optional so partial/extra payloads still decode.
/// NOTE: `type` is expected to be "movie" or "show" (movie-web convention).
struct BookmarkMeta: Codable {
    let type: String?
    let title: String?
    let year: Int?
    let poster: String?
}

/// `GET /users/{userId}/bookmarks` item.
struct BookmarkResponse: Codable {
    let tmdbId: String
    let meta: BookmarkMeta?
    let updatedAt: String?

    func toBookmark() -> Bookmark? {
        guard let id = Int(tmdbId) else { return nil }
        let isShow = (meta?.type == "show" || meta?.type == "tv")
        let date = ISO8601DateFormatter().date(from: updatedAt ?? "") ?? Date()
        return Bookmark(id: id, mediaType: isShow ? .tv : .movie, addedAt: date)
    }
}

/// Minimal body for `POST /users/{userId}/bookmarks/{tmdbId}`. The app only
/// knows the tmdbId and media type at bookmark time, so it sends a minimal
/// meta; the backend enriches the rest.
struct BookmarkInput: Encodable {
    let tmdbId: String
    let meta: MetaInput

    struct MetaInput: Encodable {
        let type: String
        let tmdbId: String
    }
}
