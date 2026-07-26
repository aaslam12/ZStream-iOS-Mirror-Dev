//
//  StreamResult.swift
//  ZStreamCore
//

import Foundation

/// The result of a single source resolution attempt.
/// Sources must never throw from resolve() — return .error instead.
public enum StreamResult {
    public struct Success {
        public let streamUrl: String
        public let streamType: String // "hls" or "file"
        public var captions: [Caption] = []
        public var headers: [String: String] = [:]
        public var codec: String = "" // e.g. "hevc", "h264", "" if unknown
        public var variants: [Variant] = [] // all available variants for the picker
        /// True if the CDN URL expires quickly after resolution (e.g. signed tokens with
        /// short TTL). When set, the app skips the HLS probe that would otherwise consume
        /// the token before the player gets it.
        public var skipProbe: Bool = false

        public init(
            streamUrl: String,
            streamType: String,
            captions: [Caption] = [],
            headers: [String: String] = [:],
            codec: String = "",
            variants: [Variant] = [],
            skipProbe: Bool = false
        ) {
            self.streamUrl = streamUrl
            self.streamType = streamType
            self.captions = captions
            self.headers = headers
            self.codec = codec
            self.variants = variants
            self.skipProbe = skipProbe
        }
    }

    /// A single playable variant returned alongside the primary stream.
    public struct Variant {
        public let id: String // unique identifier (fid)
        public let name: String // display name from API e.g. "1080p HEVC"
        public let quality: String // e.g. "4K", "1080p"
        public let codec: String // e.g. "hevc", "h264", ""
        public let tag: String // e.g. "hdr", "dv", "remux", "bw", ""
        public let streamUrl: String // decrypted HLS URL
        public var streamType: String = "hls"
        public var headers: [String: String] = [:]
        /// True if the stream URL expires shortly after resolution (e.g. signed CDN tokens).
        /// When the user switches to this variant, the app should re-resolve the source to
        /// obtain a fresh URL rather than using the cached one.
        public var requiresRefreshOnSwitch: Bool = false

        public init(
            id: String,
            name: String,
            quality: String,
            codec: String,
            tag: String,
            streamUrl: String,
            streamType: String = "hls",
            headers: [String: String] = [:],
            requiresRefreshOnSwitch: Bool = false
        ) {
            self.id = id
            self.name = name
            self.quality = quality
            self.codec = codec
            self.tag = tag
            self.streamUrl = streamUrl
            self.streamType = streamType
            self.headers = headers
            self.requiresRefreshOnSwitch = requiresRefreshOnSwitch
        }
    }

    case success(Success)
    /// Source had no result for this media (not found, region-locked, etc.). Try next source.
    case notFound
    /// A recoverable or non-recoverable error occurred. Message is for logging only.
    case error(message: String)
}
