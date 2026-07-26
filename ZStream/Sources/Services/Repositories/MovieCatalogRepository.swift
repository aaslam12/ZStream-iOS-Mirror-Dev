//
//  MovieCatalogRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Cache backed loader for TMDB Movies (latest, popular etc..)
struct MovieCatalogRepository: CacheBackedLoader {
    let cache: DiskCache = .shared
    let cacheKey = "movie_catalog"
    let ttl: TimeInterval = 60 * 60

    let settings: AppSettings

    func fetchFromNetwork() async throws -> MovieCatalog {
        async let popular = fetchPage(Movie.self, from: Endpoints.popular(type: .movie, settings: settings), auth: .tmdb)
        async let topRated = fetchPage(Movie.self, from: Endpoints.topRated(type: .movie, settings: settings), auth: .tmdb)
        async let newArrivals = fetchPage(Movie.self, from: Endpoints.newReleasesMovies(settings: settings), auth: .tmdb)
        async let featured = fetchPage(Movie.self, from: Endpoints.trending(type: .movie, settings: settings), auth: .tmdb)
        async let latest = fetchPage(Movie.self, from: Endpoints.upcomingMovies(settings: settings), auth: .tmdb)
        
        return MovieCatalog(
            popular: try await popular,
            topRated: try await topRated,
            latest: try await latest,
            newArrivals: try await newArrivals,
            featured: try await featured
        )
    }
}
