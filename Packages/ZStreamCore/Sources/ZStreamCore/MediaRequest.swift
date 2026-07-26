//
//  MediaRequest.swift
//  ZStreamCore
//

import Foundation

/// Describes the piece of media a source should resolve a stream for.
public struct MediaRequest {
    public enum MediaKind {
        case movie
        case show
    }

    public let type: MediaKind
    public let tmdbId: String
    public let season: Int?
    public let episode: Int?
    /// Optional hint: variant ID the caller wants. Sources may use this to
    /// prioritise one variant and skip others. Ignored if unrecognised.
    public let preferredVariantId: String?

    public init(type: MediaKind, tmdbId: String, season: Int? = nil, episode: Int? = nil, preferredVariantId: String? = nil) {
        self.type = type
        self.tmdbId = tmdbId
        self.season = season
        self.episode = episode
        self.preferredVariantId = preferredVariantId
    }
}
