//
//  Endpoints.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

// TODO: for multiple sources if we need we can change this to
//       Utilities/APIs/TMDB, Utilities/APIs/[other], etc... and have
//       a [Source]Endpoint.swift and [Source]Config.swift

/// TMDB URL building enumerator, helps creating helper methods to fetch the movie db safely from a single source.
enum Endpoints {
    static let base = "https://api.themoviedb.org/3"

    // Private helpers
    private static func url(path: String, extraParams: [String: String] = [:], settings: AppSettings) -> URL {
        var components = URLComponents(string: "\(base)\(path)")!
        var queryItems = [
            URLQueryItem(name: "language", value: settings.locale),
            URLQueryItem(name: "include_adult", value: String(!settings.kidMode))
        ]
        for (key, value) in extraParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = queryItems
        return components.url!
    }

    // Public endpoints
    static func popular(type: MediaType, page: Int = 1, settings: AppSettings) -> URL {
        url(path: "/\(type.rawValue)/popular", extraParams: ["page": String(page)], settings: settings)
    }

    static func topRated(type: MediaType, page: Int = 1, settings: AppSettings) -> URL {
        url(path: "/\(type.rawValue)/top_rated", extraParams: ["page": String(page)], settings: settings)
    }

    static func trending(type: MediaType? = nil, window: TrendingWindow = .day, page: Int = 1, settings: AppSettings) -> URL {
        let segment = type?.rawValue ?? "all"
        return url(path: "/trending/\(segment)/\(window.rawValue)", extraParams: ["page": String(page)], settings: settings)
    }

    static func onTheAirTV(settings: AppSettings) -> URL {
        url(path: "/tv/on_the_air", settings: settings)
    }

    static func airingTodayTV(settings: AppSettings) -> URL {
        url(path: "/tv/airing_today", settings: settings)
    }
    
    static func newReleasesMovies(page: Int = 1, settings: AppSettings) -> URL {
        url(path: "/movie/now_playing", extraParams: ["page": String(page)], settings: settings)
    }

    static func newReleasesTv(page: Int = 1, settings: AppSettings) -> URL {
        url(path: "/tv/on_the_air", extraParams: ["page": String(page)], settings: settings)
    }
    
    static func upcomingMovies(page: Int = 1, settings: AppSettings) -> URL {
        url(path: "/movie/upcoming", extraParams: ["page": String(page)], settings: settings)
    }
    
    static func movieDetail(id: Int, settings: AppSettings) -> URL {
        url(path: "/movie/\(id)", settings: settings)
    }

    static func tvDetail(id: Int, settings: AppSettings) -> URL {
        url(path: "/tv/\(id)", settings: settings)
    }

    static func movieRecommendations(id: Int, settings: AppSettings) -> URL {
        url(path: "/movie/\(id)/recommendations", settings: settings)
    }

    static func tvRecommendations(id: Int, settings: AppSettings) -> URL {
        url(path: "/tv/\(id)/recommendations", settings: settings)
    }
    
    static func tvCredits(id: Int, settings: AppSettings) -> URL {
        url(path: "/tv/\(id)/credits", settings: settings)
    }
    
    static func movieCredits(id: Int, settings: AppSettings) -> URL {
        url(path: "/movie/\(id)/credits", settings: settings)
    }

    static func movieExternalIds(id: Int, settings: AppSettings) -> URL {
        url(path: "/movie/\(id)/external_ids", settings: settings)
    }

    static func tvExternalIds(id: Int, settings: AppSettings) -> URL {
        url(path: "/tv/\(id)/external_ids", settings: settings)
    }

    static func tvSeasonDetail(tvId: Int, season: Int, settings: AppSettings) -> URL {
        url(path: "/tv/\(tvId)/season/\(season)", settings: settings)
    }
    
    static func similarMovies(id: Int, settings: AppSettings) -> URL {
        url(path: "/movie/\(id)/similar", settings: settings)
    }

    static func similarTVShows(id: Int, settings: AppSettings) -> URL {
        url(path: "/tv/\(id)/similar", settings: settings)
    }
    
    static func genreRepresentative(genreId: Int, settings: AppSettings) -> URL {
        var components = URLComponents(string: "\(base)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "with_genres", value: String(genreId)),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "language", value: settings.locale),
            URLQueryItem(name: "include_adult", value: String(!settings.kidMode))
        ]
        return components.url!
    }
    
    static func searchMulti(query: String, settings: AppSettings) -> URL {
        var components = URLComponents(string: "\(base)/search/multi")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: String(!settings.kidMode)),
            URLQueryItem(name: "language", value: settings.locale)
        ]
        return components.url!
    }
    
    static func searchCollection(query: String, settings: AppSettings) -> URL {
        var components = URLComponents(string: "\(base)/search/collection")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: settings.locale)
        ]
        return components.url!
    }

    static func collectionDetail(id: Int, settings: AppSettings) -> URL {
        url(path: "/collection/\(id)", settings: settings)
    }

    static func moviesBy(_ params: DiscoverMoviesParams, settings: AppSettings) -> URL {
        var extraParams: [String: String] = [:]

        if let year = params.primaryReleaseYear {
            extraParams["primary_release_year"] = String(year)
        }
        if let year = params.year {
            extraParams["year"] = String(year)
        }
        if let sortBy = params.sortBy {
            extraParams["sort_by"] = sortBy.rawValue
        }
        if let gte = params.voteAverageGte {
            extraParams["vote_average.gte"] = String(gte)
        }
        if let lte = params.voteAverageLte {
            extraParams["vote_average.lte"] = String(lte)
        }
        if let cast = params.withCast {
            extraParams["with_cast"] = cast.queryValue
        }
        if let genres = params.withGenres {
            extraParams["with_genres"] = genres.queryValue
        }

        return url(path: "/discover/movie", extraParams: extraParams, settings: settings)
    }
}

enum SortOption: String {
    case originalTitleAsc = "original_title.asc"
    case originalTitleDesc = "original_title.desc"
    case popularityAsc = "popularity.asc"
    case popularityDesc = "popularity.desc"
    case revenueAsc = "revenue.asc"
    case revenueDesc = "revenue.desc"
    case primaryReleaseDateAsc = "primary_release_date.asc"
    case primaryReleaseDateDesc = "primary_release_date.desc"
    case titleAsc = "title.asc"
    case titleDesc = "title.desc"
    case voteAverageAsc = "vote_average.asc"
    case voteAverageDesc = "vote_average.desc"
    case voteCountAsc = "vote_count.asc"
    case voteCountDesc = "vote_count.desc"
}

enum FilterList {
    case and([String])
    case or([String])

    var queryValue: String {
        switch self {
        case .and(let values): return values.joined(separator: ",")
        case .or(let values): return values.joined(separator: "|")
        }
    }
}

struct DiscoverMoviesParams {
    var primaryReleaseYear: Int? = nil
    var year: Int? = nil
    var sortBy: SortOption? = nil
    var voteAverageGte: Double? = nil
    var voteAverageLte: Double? = nil
    var withCast: FilterList? = nil
    var withGenres: FilterList? = nil
}
