//
//  ExportFormat.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import AVFoundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4, mov

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
    var fileExtension: String { rawValue }
}

struct MediaTrackInfo {
    let videoCodec: String?
    let resolution: String?
    let videoBitrate: String?
    let frameRate: String?
    let audioCodec: String?
    let audioChannels: String?
    let audioLanguage: String?
    let duration: String?
}
