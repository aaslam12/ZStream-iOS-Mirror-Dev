//
//  MediaType.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Enumerator to generalize the API clal
enum MediaType: String, Codable {
    case movie
    case tv
    
    var text: String {
        switch self {
            case .movie: return "Movie"
            case .tv: return "TV Show"
        }
    }
}

enum TrendingWindow: String {
    case day
    case week
    case month
    case year
}
