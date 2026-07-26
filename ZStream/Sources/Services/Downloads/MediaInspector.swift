//
//  MediaInspector.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import AVFoundation

enum MediaInspector {
    static func inspect(url: URL) async -> MediaTrackInfo {
        let asset = AVURLAsset(url: url)

        var videoCodec: String?
        var resolution: String?
        var videoBitrate: String?
        var frameRate: String?
        var audioCodec: String?
        var audioChannels: String?
        var audioLanguage: String?

        if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
            let size = try? await track.load(.naturalSize)
            if let size { resolution = "\(Int(size.width))×\(Int(size.height))" }

            let rate = try? await track.load(.estimatedDataRate)
            if let rate { videoBitrate = String(format: "%.1f Mbps", rate / 1_000_000) }

            let fps = try? await track.load(.nominalFrameRate)
            if let fps { frameRate = String(format: "%.0f fps", fps) }

            if let formats = try? await track.load(.formatDescriptions), let first = formats.first {
                videoCodec = codecName(for: CMFormatDescriptionGetMediaSubType(first))
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first {
            if let formats = try? await track.load(.formatDescriptions), let first = formats.first {
                audioCodec = codecName(for: CMFormatDescriptionGetMediaSubType(first))
                if let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(first) {
                    audioChannels = streamDesc.pointee.mChannelsPerFrame == 1 ? "Mono" : (streamDesc.pointee.mChannelsPerFrame >= 6 ? "Surround" : "Stereo")
                }
            }
            if let langCode = try? await track.load(.languageCode) {
                audioLanguage = Locale.current.localizedString(forLanguageCode: langCode) ?? langCode
            }
        }

        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
        let durationString = formatDuration(durationSeconds)

        return MediaTrackInfo(
            videoCodec: videoCodec,
            resolution: resolution,
            videoBitrate: videoBitrate,
            frameRate: frameRate,
            audioCodec: audioCodec,
            audioChannels: audioChannels,
            audioLanguage: audioLanguage,
            duration: durationString
        )
    }

    private static func codecName(for subType: FourCharCode) -> String {
        switch subType {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatAC3: return "Dolby Digital"
        case kAudioFormatEnhancedAC3: return "Dolby Atmos"
        default: return "Unknown"
        }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
