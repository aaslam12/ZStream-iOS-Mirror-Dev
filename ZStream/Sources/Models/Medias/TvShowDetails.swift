//
//  TvShowDetails.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct TvShowDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double
    let voteCount: Int
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    let genres: [Genre]
    let seasons: [SeasonSummary]

    struct Genre: Codable {
        let id: Int
        let name: String
    }

    struct SeasonSummary: Codable, Identifiable {
        let id: Int
        let seasonNumber: Int
        let name: String
        let episodeCount: Int

        enum CodingKeys: String, CodingKey {
            case id, name
            case seasonNumber = "season_number"
            case episodeCount = "episode_count"
        }
    }

    var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }

    var releaseYear: Int? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return Int(firstAirDate.prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
    }
}
