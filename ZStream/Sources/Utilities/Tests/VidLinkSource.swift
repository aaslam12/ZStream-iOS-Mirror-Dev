//
//  VidLinkSource.swift
//  ZStream
//
//  Adapts the existing VidFastResolver (public test streams) into a
//  StreamSource conformance, so it can be driven through SourceResolver
//  the same way any other source would be.
//

import Foundation
import ZStreamCore

struct VidLinkSource: StreamSource {
    let version = 1

    func availableSources() -> [SourceInfo] {
        [SourceInfo(id: "vidlink", displayName: "VidLink")]
    }

    func resolve(media: MediaRequest, sourceId: String) async -> StreamResult {
        guard sourceId == "vidlink", let tmdbId = Int(media.tmdbId) else {
            return .notFound
        }

        do {
            let playback: PlaybackSource
            if media.type == .show, let season = media.season, let episode = media.episode {
                playback = try await VidFastResolver.resolveEpisode(tmdbId: tmdbId, season: season, episode: episode)
            } else {
                playback = try await VidFastResolver.resolveMovie(tmdbId: tmdbId)
            }

            return .success(.init(
                streamUrl: playback.url.absoluteString,
                streamType: "hls",
                captions: playback.subtitles.map {
                    Caption(url: $0.url.absoluteString, language: $0.label, langIso: $0.label, type: "vtt")
                },
                headers: playback.headers ?? [:]
            ))
        } catch {
            return .error(message: "\(error)")
        }
    }
}
