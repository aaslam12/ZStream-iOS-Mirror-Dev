//
//  MediaItem.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//
import Foundation

/// Shared protocol for Movie.swift and TvShow.swift.
/// Helps the app views to treat them the same way
protocol MediaItem: Identifiable, Codable {
    var id: Int { get }
    var mediaType: MediaType { get }
    var displayTitle: String { get }
    var overview: String { get }
    var posterURL: URL? { get }
    var backdropURL: URL? { get }
    var rating: Double { get }
    var releaseYear: Int? { get }
    var isUnreleased: Bool { get }
}
