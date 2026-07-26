//
//  MediaDetailsRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/16/26.
//

import Foundation

struct MediaDetailsRepository {
    let cache: DiskCache = .shared
    let settings: AppSettings

    func movie(id: Int) async throws -> Movie {
        let key = "movie_detail_\(id)"
        if let cached = await cache.read(Movie.self, key: key), !cached.isStale(ttl: 60 * 60 * 24) {
            return cached.value
        }
        let movie = try await fetchJSON(Movie.self, from: Endpoints.movieDetail(id: id, settings: settings), auth: .tmdb)
        await cache.write(movie, key: key)
        return movie
    }

    func tvShow(id: Int) async throws -> TVShow {
        let key = "tv_detail_\(id)"
        if let cached = await cache.read(TVShow.self, key: key), !cached.isStale(ttl: 60 * 60 * 24) {
            return cached.value
        }
        let show = try await fetchJSON(TVShow.self, from: Endpoints.tvDetail(id: id, settings: settings), auth: .tmdb)
        await cache.write(show, key: key)
        return show
    }

    func recommendedMovies(forMovieId id: Int) async throws -> [Movie] {
        try await fetchPage(Movie.self, from: Endpoints.movieRecommendations(id: id, settings: settings), auth: .tmdb)
    }

    func recommendedTVShows(forTVShowId id: Int) async throws -> [TVShow] {
        try await fetchPage(TVShow.self, from: Endpoints.tvRecommendations(id: id, settings: settings), auth: .tmdb)
    }

    func movieDetail(id: Int) async throws -> MovieDetail {
        let key = "movie_full_detail_\(id)"
        if let cached = await cache.read(MovieDetail.self, key: key), !cached.isStale(ttl: 60 * 60 * 24) {
            return cached.value
        }
        let detail = try await fetchJSON(MovieDetail.self, from: Endpoints.movieDetail(id: id, settings: settings), auth: .tmdb)
        await cache.write(detail, key: key)
        return detail
    }

    func tvDetail(id: Int) async throws -> TvShowDetail {
        let key = "tv_full_detail_\(id)"
        if let cached = await cache.read(TvShowDetail.self, key: key), !cached.isStale(ttl: 60 * 60 * 24) {
            return cached.value
        }
        let detail = try await fetchJSON(TvShowDetail.self, from: Endpoints.tvDetail(id: id, settings: settings), auth: .tmdb)
        await cache.write(detail, key: key)
        return detail
    }

    func movieCredits(id: Int) async throws -> Credits {
        let key = "movie_credits_\(id)"
        if let cached = await cache.read(Credits.self, key: key), !cached.isStale(ttl: 60 * 60 * 24) {
            return cached.value
        }
        let credits = try await fetchJSON(Credits.self, from: Endpoints.movieCredits(id: id, settings: settings), auth: .tmdb)
        await cache.write(credits, key: key)
        return credits
    }

    func tvCredits(id: Int) async throws -> Credits {
        let key = "tv_credits_\(id)"
        if let cached = await cache.read(Credits.self, key: key), !cached.isStale(ttl: 60 * 60 * 24) {
            return cached.value
        }
        let credits = try await fetchJSON(Credits.self, from: Endpoints.tvCredits(id: id, settings: settings), auth: .tmdb)
        await cache.write(credits, key: key)
        return credits
    }

    func similarMovies(id: Int) async throws -> [Movie] {
        try await fetchPage(Movie.self, from: Endpoints.similarMovies(id: id, settings: settings), auth: .tmdb)
    }

    func similarTVShows(id: Int) async throws -> [TVShow] {
        try await fetchPage(TVShow.self, from: Endpoints.similarTVShows(id: id, settings: settings), auth: .tmdb)
    }

    func movieExternalIds(id: Int) async throws -> ExternalIds {
        try await fetchJSON(ExternalIds.self, from: Endpoints.movieExternalIds(id: id, settings: settings), auth: .tmdb)
    }

    func tvExternalIds(id: Int) async throws -> ExternalIds {
        try await fetchJSON(ExternalIds.self, from: Endpoints.tvExternalIds(id: id, settings: settings), auth: .tmdb)
    }

    func seasonDetail(tvId: Int, season: Int) async throws -> SeasonDetail {
        try await fetchJSON(SeasonDetail.self, from: Endpoints.tvSeasonDetail(tvId: tvId, season: season, settings: settings), auth: .tmdb)
    }
}
