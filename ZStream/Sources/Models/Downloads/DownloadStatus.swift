//
//  DownloadStatus.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

enum DownloadStatus: Equatable {
    case queued
    case downloading(progress: Double) // 0...1
    case paused(progress: Double)
    case failed(String)

    /// The 0...1 progress, if this status carries one (downloading/paused).
    var progressValue: Double? {
        switch self {
        case .downloading(let p), .paused(let p): return p
        case .queued, .failed: return nil
        }
    }
}

/// Per-episode metadata carried alongside a TV download so it can be persisted
/// on the DownloadRecord (for grouping by show and listing "1. Pilot"). Nil for
/// movies.
struct EpisodeInfo: Equatable, Codable {
    let showTitle: String
    let seasonNumber: Int
    let episodeNumber: Int
    let episodeTitle: String
    let stillPath: String?
}

/// A download currently in progress — in-memory only. If the app relaunches
/// mid-download, this list starts empty; a real engine (AVAssetDownloadTask)
/// would resume from its own background session instead of this struct.
struct ActiveDownload: Identifiable, Equatable {
    let id: String
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    var status: DownloadStatus
    var episodeInfo: EpisodeInfo? = nil
    /// Bytes transferred / expected so far, as reported by the underlying
    /// URLSessionTask. Expected is AVFoundation's running estimate — it can
    /// shift slightly as more of the asset's structure becomes known, so
    /// treat it as approximate, not a hard final size.
    var bytesReceived: Int64 = 0
    var bytesExpected: Int64 = 0

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }
}
