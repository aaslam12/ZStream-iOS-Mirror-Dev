//
//  DownloadQualityResolver.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/24/26.
//

import AVFoundation

/// One resolution a source's master playlist actually offers, with its
/// peak bitrate so the picker can show an approximate file size.
struct DownloadQualityOption: Identifiable, Equatable {
    let level: PlayerQuality.Level
    let approxBitrate: Double // bits/sec; 0 if the playlist didn't report one
    var id: PlayerQuality.Level { level }
}

/// Reads a stream's HLS master playlist (through the same proxy used for
/// playback/downloading) to discover which resolutions are actually
/// available, so the user can pick a size before committing to a download —
/// previously downloads always grabbed the highest-bitrate rendition, which
/// for a 4K movie can mean 15-20GB with no way to choose something smaller.
enum DownloadQualityResolver {
    static func availableQualities(for streamURL: URL, headers: [String: String]?) async -> [DownloadQualityOption] {
        // Same construction as DownloadManager.startRawDownload: non-cacheable,
        // same headers — so what we inspect here matches what would actually
        // be fetched.
        let proxiedURL = HLSPlaybackProxy.playbackURL(for: streamURL, extraHeaders: headers, cacheable: false)
        let asset = AVURLAsset(url: proxiedURL)
        guard let variants = try? await asset.load(.variants), !variants.isEmpty else {
            return []
        }

        var mapping: [PlayerQuality.Level: Double] = [:]
        for variant in variants {
            guard let h = variant.videoAttributes?.presentationSize.height, h > 0 else { continue }
            let level = PlayerQuality.Level.level(forHeight: Int(h))
            let bitrate = variant.peakBitRate ?? variant.averageBitRate ?? 0
            if let existing = mapping[level], existing >= bitrate { continue }
            mapping[level] = bitrate
        }

        return PlayerQuality.Level.allCases
            .compactMap { level -> DownloadQualityOption? in
                guard level != .auto, let bitrate = mapping[level] else { return nil }
                return DownloadQualityOption(level: level, approxBitrate: bitrate)
            }
            .sorted { ($0.level.maxHeight ?? 0) > ($1.level.maxHeight ?? 0) }
    }
}
