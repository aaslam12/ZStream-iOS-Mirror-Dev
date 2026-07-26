//
//  MediaItemDetailsState.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct MediaItemReference: Identifiable, Equatable {
    let mediaId: Int
    let mediaType: MediaType

    var id: String { "\(mediaType.rawValue)-\(mediaId)" }
}


@MainActor
final class MediaItemDetailState: ObservableObject {
    @Published var movieDetail: MovieDetail?
    @Published var tvDetail: TvShowDetail?
    @Published var credits: Credits?
    @Published var externalIds: ExternalIds?
    @Published var selectedSeason: Int = 1
    @Published var seasonEpisodes: [SeasonDetail.Episode] = []
    @Published var similarItems: [any MediaItem] = []

    private let reference: MediaItemReference
    private let repo: MediaDetailsRepository

    init(reference: MediaItemReference, settings: AppSettings) {
        self.reference = reference
        self.repo = MediaDetailsRepository(settings: settings)
    }

    func load() async {
        switch reference.mediaType {
        case .movie:
            async let detail = repo.movieDetail(id: reference.mediaId)
            async let credits = repo.movieCredits(id: reference.mediaId)
            async let external = repo.movieExternalIds(id: reference.mediaId)
            async let similar = repo.similarMovies(id: reference.mediaId)
            movieDetail = try? await detail
            self.credits = try? await credits
            externalIds = try? await external
            similarItems = (try? await similar) ?? []

        case .tv:
            async let detail = repo.tvDetail(id: reference.mediaId)
            async let credits = repo.tvCredits(id: reference.mediaId)
            async let external = repo.tvExternalIds(id: reference.mediaId)
            async let similar = repo.similarTVShows(id: reference.mediaId)
            tvDetail = try? await detail
            self.credits = try? await credits
            externalIds = try? await external
            similarItems = (try? await similar) ?? []

            if let firstSeason = tvDetail?.seasons.first(where: { $0.seasonNumber > 0 })?.seasonNumber {
                await loadSeason(firstSeason)
            }
        }
    }

    func loadSeason(_ season: Int) async {
        selectedSeason = season
        seasonEpisodes = (try? await repo.seasonDetail(tvId: reference.mediaId, season: season).episodes) ?? []
    }

    /// Fetches a season's episodes without touching the currently-selected
    /// season/UI — used to queue a whole-season download.
    func fetchEpisodes(forSeason season: Int) async -> [SeasonDetail.Episode] {
        (try? await repo.seasonDetail(tvId: reference.mediaId, season: season).episodes) ?? []
    }
}
