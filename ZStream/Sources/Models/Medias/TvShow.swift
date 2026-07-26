//
//  TvShow.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//
import Foundation

/// Decodes a TMDB Tv show response
struct TVShow: MediaItem {
    let id: Int
    let name: String
    let originalName: String
    let originalLanguage: String
    let originCountry: [String]
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let genreIds: [Int]
    let popularity: Double
    let voteAverage: Double
    let voteCount: Int

    var mediaType: MediaType { .tv }
    var displayTitle: String { name }
    var rating: Double { voteAverage }

    // Composed from path fragments
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    // Composed from path fragments
    var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(backdropPath)")
    }

    var releaseYear: Int? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return Int(firstAirDate.prefix(4))
    }
    
    var isUnreleased: Bool {
        ReleaseDateHelper.isFutureRelease(firstAirDate)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, popularity
        case originalName = "original_name"
        case originalLanguage = "original_language"
        case originCountry = "origin_country"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case genreIds = "genre_ids"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}
