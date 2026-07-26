//
//  TVCatalogRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Cache backed loader for TMDB tv shows (latest, popular etc..)
struct TVCatalogRepository: CacheBackedLoader {
    let cache: DiskCache = .shared
    let cacheKey = "tv_catalog"
    let ttl: TimeInterval = 60 * 60
    let settings: AppSettings

    func fetchFromNetwork() async throws -> TVCatalog {
        async let popular = fetchPage(TVShow.self, from: Endpoints.popular(type: .tv, settings: settings), auth: .tmdb)
        async let topRated = fetchPage(TVShow.self, from: Endpoints.topRated(type: .tv, settings: settings), auth: .tmdb)
        async let newArrivals = fetchPage(TVShow.self, from: Endpoints.airingTodayTV(settings: settings), auth: .tmdb)
        async let featured = fetchPage(TVShow.self, from: Endpoints.trending(type: .tv, settings: settings), auth: .tmdb)
        async let latest = fetchPage(TVShow.self, from: Endpoints.onTheAirTV(settings: settings), auth: .tmdb)

        return TVCatalog(
            popular: try await popular,
            topRated: try await topRated,
            latest: try await latest,
            newArrivals: try await newArrivals,
            featured: try await featured
        )
    }
}
