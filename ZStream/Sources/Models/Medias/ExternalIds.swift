//
//  ExternalIds.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct ExternalIds: Codable {
    let imdbId: String?

    var imdbURL: URL? {
        guard let imdbId else { return nil }
        return URL(string: "https://www.imdb.com/title/\(imdbId)")
    }

    enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
    }
}
