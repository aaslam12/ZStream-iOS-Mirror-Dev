//
//  SeasonDetail.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct SeasonDetail: Codable {
    let episodes: [Episode]

    struct Episode: Codable, Identifiable {
        let id: Int
        let episodeNumber: Int
        let name: String
        let overview: String
        let stillPath: String?
        let airDate: String?

        var stillURL: URL? {
            guard let stillPath else { return nil }
            return URL(string: "https://image.tmdb.org/t/p/w300\(stillPath)")
        }

        /// True if this episode's air date is in the future (or unknown air
        /// dates for a show that's already released are treated as aired —
        /// only a *known future* date should block downloading/playing).
        var isUnaired: Bool {
            guard let airDate, let date = Episode.dateFormatter.date(from: airDate) else { return false }
            return date > Date()
        }

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return f
        }()

        enum CodingKeys: String, CodingKey {
            case id, name, overview
            case episodeNumber = "episode_number"
            case stillPath = "still_path"
            case airDate = "air_date"
        }
    }
}
