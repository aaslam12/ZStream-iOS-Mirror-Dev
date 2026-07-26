//
//  PlaybackSource.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

/// An external subtitle track (WebVTT) that ships alongside the stream.
struct PlaybackSubtitle: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let url: URL
}

struct PlaybackSource {
    let url: URL
    let headers: [String: String]?
    /// When true (the default), remote streams are routed through the local HLS
    /// proxy that fixes disguised segment content-types. The video tester plays
    /// arbitrary URLs directly (proxy off), so standard MP4/HLS aren't re-typed.
    let useProxy: Bool
    /// External subtitle tracks resolved with the source. Rendered by the app's
    /// own overlay (AVPlayer can't ingest arbitrary standalone VTT URLs).
    let subtitles: [PlaybackSubtitle]
    /// Which StreamSource (SourceInfo.id) produced this stream, when known —
    /// lets the player pre-check the active source in its source menu. Nil for
    /// local files and other flows that never went through SourceResolver.
    let sourceId: String?

    init(url: URL, headers: [String: String]? = nil, useProxy: Bool = true, subtitles: [PlaybackSubtitle] = [], sourceId: String? = nil) {
        self.url = url
        self.headers = headers
        self.useProxy = useProxy
        self.subtitles = subtitles
        self.sourceId = sourceId
    }
}
