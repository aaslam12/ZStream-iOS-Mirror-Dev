//
//  RecentlyWatchedItems.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// A movie or tv show recently watched by the user
struct RecentlyWatched: Codable, Identifiable, Equatable {
    let id: Int
    let mediaType: MediaType
    var progress: Double // 0.0 - 1.0
    var lastWatchedAt: Date
}
