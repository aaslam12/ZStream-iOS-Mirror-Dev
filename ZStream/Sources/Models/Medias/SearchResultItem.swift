//
//  SearchResultItem.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

enum SearchResultItem: Identifiable, Decodable {
    case movie(Movie)
    case tv(TVShow)
    case person

    var id: String {
        switch self {
        case .movie(let m): return "movie-\(m.id)"
        case .tv(let t): return "tv-\(t.id)"
        case .person: return UUID().uuidString
        }
    }

    var mediaItem: (any MediaItem)? {
        switch self {
        case .movie(let m): return m
        case .tv(let t): return t
        case .person: return nil
        }
    }

    private enum CodingKeys: String, CodingKey { case mediaType = "media_type" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .mediaType)
        switch type {
        case "movie": self = .movie(try Movie(from: decoder))
        case "tv": self = .tv(try TVShow(from: decoder))
        default: self = .person
        }
    }
}
