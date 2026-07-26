//
//  Bootstrapper.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Runs a startup sequence for the app, loads user profile, recently watched, bookmarks, movies/tv shows, etc...
/// Stores the result inside ContentStore
@MainActor
final class Bootstrapper: ObservableObject {
    enum Phase: Equatable {
        case notStarted
        case loadingCore
        case loadingLibrary
        case loadingCatalog
        case ready
    }

    @Published private(set) var phase: Phase = .notStarted

    private let contentStore: ContentStore
    private let profileStore = ProfileStore()
    private let recentlyWatchedRepo = RecentlyWatchedRepository()
    private let bookmarksRepo = BookmarksRepository()
    private let movieCatalogRepo: MovieCatalogRepository
    private let tvCatalogRepo: TVCatalogRepository

    init(contentStore: ContentStore, settings: AppSettings) {
        self.contentStore = contentStore
        self.movieCatalogRepo = MovieCatalogRepository(settings: settings)
        self.tvCatalogRepo = TVCatalogRepository(settings: settings)
    }

    func start() async {
        guard phase == .notStarted else { return } // prevents double-run if called twice

        phase = .loadingCore
        contentStore.profile = await profileStore.load()

        phase = .loadingLibrary
        async let recent = try? recentlyWatchedRepo.load()
        async let marks = try? bookmarksRepo.load()
        let (recentResult, marksResult) = await (recent, marks)
        contentStore.recentlyWatched = recentResult ?? []
        contentStore.bookmarks = marksResult ?? []

        phase = .loadingCatalog
        do {
            contentStore.movieCatalog = try await movieCatalogRepo.load()
        } catch {
            print("Movie catalog fetch failed: \(error.localizedDescription)")
            contentStore.movieCatalog = .empty
        }
        
        async let shows = try? tvCatalogRepo.load()
        let showResult = await shows
        contentStore.tvCatalog = showResult ?? .empty

        // Step 5
        phase = .ready
    }
}
