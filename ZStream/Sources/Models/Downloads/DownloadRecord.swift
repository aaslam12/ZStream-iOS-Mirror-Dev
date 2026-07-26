//
//  DownloadRecord.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

/// A completed download's metadata — persisted. Represents "what's on disk,"
/// not "what's currently transferring" (that's DownloadManager's in-memory job).
struct DownloadRecord: Codable, Identifiable, Equatable {
    let id: String // "movie-550" style, matches MediaItemReference
    let mediaId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let fileSizeBytes: Int64
    let downloadedAt: Date
    let localFileName: String

    // TV-episode metadata (nil for movies and for records created before this
    // was added — all optional so old persisted downloads still decode).
    var showTitle: String? = nil
    var seasonNumber: Int? = nil
    var episodeNumber: Int? = nil
    var episodeTitle: String? = nil
    var episodeStillPath: String? = nil

    /// The asset's actual on-disk location, as reported by AVFoundation via
    /// `willDownloadToURL:`. Apple's guidance is explicit that this location
    /// is final and must not be moved/copied, so — unlike every other file
    /// this app manages — a download's package does NOT live under
    /// `DownloadStorage.directory`; it lives wherever AVFoundation decided.
    /// Nil only for records persisted before this field existed, which
    /// predate that discovery and did move the file into DownloadStorage —
    /// `resolvedFileURL` falls back to the old behavior for those.
    var localFileURL: URL? = nil

    /// Where this download's package actually lives on disk right now.
    var resolvedFileURL: URL {
        localFileURL ?? DownloadStorage.fileURL(named: localFileName)
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    /// The episode's still frame (TMDB), matching what MediaItemDialog shows.
    var episodeStillURL: URL? {
        guard let episodeStillPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(episodeStillPath)")
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// True when this record is a single TV episode (vs. a movie).
    var isEpisode: Bool {
        mediaType == .tv && episodeNumber != nil
    }

    /// The show's name for grouping/headers — falls back to the part of the
    /// stored title before the " — SxEy" suffix for older records.
    var showDisplayTitle: String {
        showTitle ?? title.components(separatedBy: " — ").first ?? title
    }

    /// "1 - Pilot" for the episode list; degrades gracefully when the name or
    /// number is missing on older records.
    var episodeListLabel: String {
        switch (episodeNumber, episodeTitle) {
        case let (num?, name?): return "\(num) - \(name)"
        case let (num?, nil): return "Episode \(num)"
        default: return title
        }
    }
}
