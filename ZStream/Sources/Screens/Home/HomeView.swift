//
//  HomeView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var contentStore: ContentStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var downloadManager: DownloadManager
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedReference: MediaItemReference?
    @State private var heroPlayback: HeroPlayback?
    @State private var heroError: String?

    @StateObject private var forYouStore: PaginatedMediaRowStore
    @StateObject private var onTheAirStore: PaginatedMediaRowStore
    @StateObject private var topRatedStore: PaginatedMediaRowStore
    @StateObject private var mostPopularStore: PaginatedMediaRowStore


    init() {
        _forYouStore = StateObject(wrappedValue: PaginatedMediaRowStore { page, settings in
            async let movies = fetchPagedResponse(Movie.self, from: Endpoints.trending(type: .movie, page: page, settings: settings), auth: .tmdb)
            async let shows = fetchPagedResponse(TVShow.self, from: Endpoints.trending(type: .tv, page: page, settings: settings), auth: .tmdb)
            let (movieResult, showResult) = try await (movies, shows)
            return interleave(movieResult.results, showResult.results)
        })
        
        _onTheAirStore = StateObject(wrappedValue: PaginatedMediaRowStore { page, settings in
            async let movies = fetchPagedResponse(Movie.self, from: Endpoints.newReleasesMovies(page: page, settings: settings), auth: .tmdb)
            async let shows = fetchPagedResponse(TVShow.self, from: Endpoints.newReleasesTv(page: page, settings: settings), auth: .tmdb)
            let (movieResult, showResult) = try await (movies, shows)
            return interleave(movieResult.results, showResult.results)
        })
        
        _topRatedStore = StateObject(wrappedValue: PaginatedMediaRowStore { page, settings in
            async let movies = fetchPagedResponse(Movie.self, from: Endpoints.trending(type: .movie, page: page, settings: settings), auth: .tmdb)
            async let shows = fetchPagedResponse(TVShow.self, from: Endpoints.trending(type: .tv, page: page, settings: settings), auth: .tmdb)
            let (movieResult, showResult) = try await (movies, shows)
            return interleave(movieResult.results, showResult.results)
        })
        
        _mostPopularStore = StateObject(wrappedValue: PaginatedMediaRowStore { page, settings in
            async let movies = fetchPagedResponse(Movie.self, from: Endpoints.popular(type: .movie, page: page, settings: settings), auth: .tmdb)
            async let shows = fetchPagedResponse(TVShow.self, from: Endpoints.popular(type: .tv, page: page, settings: settings), auth: .tmdb)
            let (movieResult, showResult) = try await (movies, shows)
            return interleave(movieResult.results, showResult.results)
        })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThemeBackground(theme: settings.theme)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    let sections = dedupedSections

                    ImageCarousel(items: sections.hero, onSelect: select, onPlay: playHero)
                    MediaRow(
                        title: "Continue Watching",
                        items: viewModel.recentlyWatchedItems,
                        onSelect: select,
                        menu: { homeItemMenu(for: $0, isContinueWatching: true) },
                        animatesItemChanges: true
                    )
                    MediaRow(
                        title: "Bookmarks",
                        items: viewModel.bookmarkedItems,
                        onSelect: select,
                        menu: { homeItemMenu(for: $0, isContinueWatching: false) },
                        animatesItemChanges: true
                    )

                    MediaRow(
                        title: "For You",
                        items: forYouStore.items,
                        onSelect: select,
                        onAppearAtIndex: { index in
                            forYouStore.loadMoreIfNeeded(currentIndex: index, settings: settings)
                        },
                        isLoadingMore: forYouStore.isLoadingMore,
                        menu: { homeItemMenu(for: $0, isContinueWatching: false) }
                    )

                    if let title = viewModel.reccommendationsTitle {
                        MediaRow(
                            title: title,
                            items: sections.reccomendations,
                            onSelect: select,
                            menu: { homeItemMenu(for: $0, isContinueWatching: false) }
                        )
                    }

                    MediaRow(
                        title: "On The Air",
                        items: onTheAirStore.items,
                        onSelect: select,
                        onAppearAtIndex: { index in
                            onTheAirStore.loadMoreIfNeeded(currentIndex: index, settings: settings)
                        },
                        isLoadingMore: onTheAirStore.isLoadingMore,
                        menu: { homeItemMenu(for: $0, isContinueWatching: false) }
                    )

                    MediaRow(
                        title: "Top Rated",
                        items: topRatedStore.items,
                        onSelect: select,
                        onAppearAtIndex: { index in
                            topRatedStore.loadMoreIfNeeded(currentIndex: index, settings: settings)
                        },
                        isLoadingMore: topRatedStore.isLoadingMore,
                        menu: { homeItemMenu(for: $0, isContinueWatching: false) }
                    )

                    MediaRow(
                        title: "Most Popular",
                        items: mostPopularStore.items,
                        onSelect: select,
                        onAppearAtIndex: { index in
                            mostPopularStore.loadMoreIfNeeded(currentIndex: index, settings: settings)
                        },
                        isLoadingMore: mostPopularStore.isLoadingMore,
                        menu: { homeItemMenu(for: $0, isContinueWatching: false) }
                    )
                }
            }
            .ignoresSafeArea(edges: .top)

            AppLogoBadge()
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
        .task {
            await viewModel.load(recentlyWatched: contentStore.recentlyWatched, bookmarks: contentStore.bookmarks, settings: settings)

            let sections = dedupedSections
            forYouStore.seed(with: sections.forYou)
            onTheAirStore.seed(with: sections.onTheAir)
            topRatedStore.seed(with: sections.topRated)
            mostPopularStore.seed(with: sections.mostPopular)
        }
        .onChange(of: contentStore.bookmarks) { _, newValue in
            Task { await viewModel.syncBookmarks(newValue, settings: settings) }
        }
        .sheet(item: $selectedReference) { reference in
            MediaItemDialog(
                reference: reference,
                settings: settings,
                onNavigate: { newReference in
                    selectedReference = newReference
                }
            )
            .id(reference.id)
        }
        .fullScreenCover(item: $heroPlayback) { playback in
            PlayerView(source: playback.source, reference: playback.reference)
        }
        .alert("Playback Unavailable", isPresented: Binding(
            get: { heroError != nil },
            set: { if !$0 { heroError = nil } }
        )) {
            Button("OK", role: .cancel) { heroError = nil }
        } message: {
            Text(heroError ?? "")
        }
    }

    private func select(_ item: any MediaItem) {
        selectedReference = MediaItemReference(mediaId: item.id, mediaType: item.mediaType)
    }

    // MARK: - Poster context menu (3D-touch)

    /// Long-press menu for a home poster. In Continue Watching, a "Remove" row is
    /// added at the top.
    private func homeItemMenu(for item: any MediaItem, isContinueWatching: Bool) -> AnyView {
        let bookmarked = isBookmarked(item)
        return AnyView(
            Group {
                if isContinueWatching {
                    Button(role: .destructive) {
                        removeFromContinueWatching(item)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }

                if let url = tmdbURL(item) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }

                Button {
                    download(item)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }

                Button {
                    toggleBookmark(item)
                } label: {
                    Label(bookmarked ? "Remove from Bookmarks" : "Add to Bookmarks",
                          systemImage: bookmarked ? "bookmark.slash" : "bookmark")
                }

                Button {
                    playHero(item)
                } label: {
                    Label("Watch", systemImage: "play.fill")
                }

                Button {
                    select(item)
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
            }
        )
    }

    private func isBookmarked(_ item: any MediaItem) -> Bool {
        contentStore.bookmarks.contains { $0.id == item.id && $0.mediaType == item.mediaType }
    }

    private func toggleBookmark(_ item: any MediaItem) {
        let id = item.id
        let type = item.mediaType
        let repo = BookmarksRepository()
        if isBookmarked(item) {
            contentStore.bookmarks.removeAll { $0.id == id && $0.mediaType == type }
            withAnimation(.easeInOut(duration: 0.28)) {
                viewModel.bookmarkedItems.removeAll { $0.id == id && $0.mediaType == type }
            }
            Task { await repo.remove(id: id, mediaType: type) }
        } else {
            contentStore.bookmarks.append(Bookmark(id: id, mediaType: type, addedAt: Date()))
            // Update the visible Bookmarks row immediately — the menu already
            // handed us the resolved item, so no re-fetch/tab-switch is needed.
            if !viewModel.bookmarkedItems.contains(where: { $0.id == id && $0.mediaType == type }) {
                withAnimation(.easeInOut(duration: 0.28)) {
                    viewModel.bookmarkedItems.insert(item, at: 0)
                }
            }
            Task { await repo.add(Bookmark(id: id, mediaType: type, addedAt: Date())) }
        }
    }

    private func removeFromContinueWatching(_ item: any MediaItem) {
        let id = item.id
        let type = item.mediaType
        contentStore.recentlyWatched.removeAll { $0.id == id && $0.mediaType == type }
        withAnimation(.easeInOut(duration: 0.28)) {
            viewModel.recentlyWatchedItems.removeAll { $0.id == id && $0.mediaType == type }
        }
        Task { await RecentlyWatchedRepository().remove(id: id, mediaType: type) }
    }

    private func download(_ item: any MediaItem) {
        // Movies download directly; shows open the detail sheet to pick a season.
        guard item.mediaType == .movie else {
            select(item)
            return
        }
        let id = item.id
        let displayTitle = item.displayTitle
        Task {
            guard let source = try? await TestStreamCatalog.source(forMovieId: id) else { return }
            await downloadManager.start(
                mediaId: id,
                mediaType: .movie,
                title: displayTitle,
                posterPath: nil,
                streamURL: source.url,
                headers: source.headers
            )
        }
    }

    private func tmdbURL(_ item: any MediaItem) -> URL? {
        let path = item.mediaType == .movie ? "movie" : "tv"
        return URL(string: "https://www.themoviedb.org/\(path)/\(item.id)")
    }

    /// Hero "Watch": plays movies directly (preferring an offline copy). Shows
    /// are opened in the detail sheet instead, so the user can pick an episode.
    private func playHero(_ item: any MediaItem) {
        guard item.mediaType == .movie else {
            select(item)
            return
        }
        Task {
            do {
                let source: PlaybackSource
                if let record = downloadManager.completedDownloads.first(where: { $0.id == "movie-\(item.id)" }) {
                    source = PlaybackSource(url: record.resolvedFileURL)
                } else {
                    source = try await TestStreamCatalog.source(forMovieId: item.id)
                }
                heroPlayback = HeroPlayback(
                    source: source,
                    reference: MediaItemReference(mediaId: item.id, mediaType: .movie)
                )
            } catch {
                heroError = "Couldn't start playback. This title may be unavailable."
            }
        }
    }

    
    private var dedupedSections: (
        hero: [any MediaItem],
        forYou: [any MediaItem],
        reccomendations: [any MediaItem],
        onTheAir: [any MediaItem],
        topRated: [any MediaItem],
        mostPopular: [any MediaItem]
    ) {
        var deduper = MediaDeduplicator()

        let hero = deduper.filter(Array(contentStore.movieCatalog.featured.prefix(6)), minimumCount: 3)
        let forYou = deduper.filter(contentStore.movieCatalog.featured)
        let reccommendations = deduper.filter(viewModel.reccommendations)
        let onTheAir = deduper.filter(contentStore.movieCatalog.latest)
        let topRated = deduper.filter(contentStore.movieCatalog.topRated)
        let mostPopular = deduper.filter(contentStore.movieCatalog.popular)

        return (hero, forYou, reccommendations, onTheAir, topRated, mostPopular)
    }
}

/// Bundles what the hero "Watch" button needs to present the player.
private struct HeroPlayback: Identifiable {
    let id = UUID()
    let source: PlaybackSource
    let reference: MediaItemReference
}

