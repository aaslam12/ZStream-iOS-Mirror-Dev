//
//  HomeViewState.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/16/26.
//

import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recentlyWatchedItems: [any MediaItem] = []
    @Published var bookmarkedItems: [any MediaItem] = []
    @Published var reccommendationsTitle: String?
    @Published var reccommendations: [any MediaItem] = []

    func load(recentlyWatched: [RecentlyWatched], bookmarks: [Bookmark], settings: AppSettings) async {
        let repo = MediaDetailsRepository(settings: settings)

        recentlyWatchedItems = await resolve(recentlyWatched.map { ($0.id, $0.mediaType) }, using: repo)
        bookmarkedItems = await resolve(bookmarks.map { ($0.id, $0.mediaType) }, using: repo)

        if let mostRecent = recentlyWatched.first {
            await loadRecommendations(basedOn: mostRecent, using: repo)
        }
    }

    /// Re-resolves just the Bookmarks row from the current `ContentStore.bookmarks`.
    /// Called whenever that list changes (e.g. bookmarking from a detail sheet
    /// opened from Search/Downloads/WatchHistory, not just from Home itself) so
    /// the row updates immediately instead of waiting for the next full `load()`
    /// — items are 24h-cached, so this is cheap. Skips the (animated) rows Home's
    /// own toggle already applied optimistically, so it doesn't fight that
    /// animation by snapping in a freshly-resolved array right behind it.
    func syncBookmarks(_ bookmarks: [Bookmark], settings: AppSettings) async {
        let currentIds = Set(bookmarkedItems.map { "\($0.id)-\($0.mediaType.rawValue)" })
        let targetIds = Set(bookmarks.map { "\($0.id)-\($0.mediaType.rawValue)" })
        guard currentIds != targetIds else { return }

        let repo = MediaDetailsRepository(settings: settings)
        bookmarkedItems = await resolve(bookmarks.map { ($0.id, $0.mediaType) }, using: repo)
    }

    private func resolve(_ entries: [(id: Int, type: MediaType)], using repo: MediaDetailsRepository) async -> [any MediaItem] {
        var results: [any MediaItem] = []
        for entry in entries {
            if let item = try? await fetchItem(id: entry.id, type: entry.type, using: repo) {
                results.append(item)
            }
        }
        return results
    }

    private func fetchItem(id: Int, type: MediaType, using repo: MediaDetailsRepository) async throws -> any MediaItem {
        switch type {
        case .movie: return try await repo.movie(id: id)
        case .tv: return try await repo.tvShow(id: id)
        }
    }

    private func loadRecommendations(basedOn entry: RecentlyWatched, using repo: MediaDetailsRepository) async {
        do {
            switch entry.mediaType {
            case .movie:
                let anchor = try await repo.movie(id: entry.id)
                reccommendationsTitle = "Because you watched \(anchor.displayTitle)"
                reccommendations = try await repo.recommendedMovies(forMovieId: entry.id)
            case .tv:
                let anchor = try await repo.tvShow(id: entry.id)
                reccommendationsTitle = "Because you watched \(anchor.displayTitle)"
                reccommendations = try await repo.recommendedTVShows(forTVShowId: entry.id)
            }
        } catch {
            reccommendationsTitle = nil
            reccommendations = []
        }
    }
}
