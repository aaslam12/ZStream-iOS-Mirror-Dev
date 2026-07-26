//
//  MediaCatalog.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Generic grouping for MovieCatalog.swift and TVCatalog.swift
struct MediaCatalog<T: Codable>: Codable {
    var popular: [T]
    var topRated: [T]
    var latest: [T]
    var newArrivals: [T]
    var featured: [T]

    static var empty: MediaCatalog<T> {
        .init(popular: [], topRated: [], latest: [], newArrivals: [], featured: [])
    }
}

// Aliases
typealias MovieCatalog = MediaCatalog<Movie>
typealias TVCatalog = MediaCatalog<TVShow>
