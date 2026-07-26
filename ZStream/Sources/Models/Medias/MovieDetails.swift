//
//  MovieDetails.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct MovieDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let overview: String
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let voteAverage: Double
    let voteCount: Int
    let genres: [Genre]
    let budget: Int
    let revenue: Int
    let status: String
    let productionCountries: [ProductionCountry]

    struct Genre: Codable {
        let id: Int
        let name: String
    }
    
    struct ProductionCountry: Codable {
        let iso3166_1: String
        let name: String

        enum CodingKeys: String, CodingKey {
            case iso3166_1 = "iso_3166_1"
            case name
        }
    }
    
    var revenueFormatted: String? {
        guard revenue > 0 else { return nil }

        let value = Double(revenue)

        if value >= 1_000_000_000 {
            return formatted(value / 1_000_000_000, suffix: "B")
        } else if value >= 1_000_000 {
            return formatted(value / 1_000_000, suffix: "M")
        } else {
            let rounded = (revenue / 1000) * 1000
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            let numberString = formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
            return "$\(numberString)"
        }
    }

    private func formatted(_ value: Double, suffix: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let numberString = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "$\(numberString)\(suffix)"
    }

    var countryNames: [String] {
        productionCountries.map(\.name)
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var backdropURL: URL? {
        guard let backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
    }

    var runtimeFormatted: String? {
        guard let runtime else { return nil }
        let hours = runtime / 60
        let minutes = runtime % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, overview, tagline, runtime, genres, budget, revenue, status
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case productionCountries = "production_countries"
    }
}
