//
//  SystemVolumeController.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import MediaPlayer
import UIKit

/// Drives the real system volume via MPVolumeView's embedded slider — the
/// standard, App-Store-safe technique for this (no private API symbols,
/// just navigating a known public view's subviews). Must be added to an
/// actual window for its slider to initialize.
final class SystemVolumeController {
    static let shared = SystemVolumeController()
    private let volumeView = MPVolumeView(frame: .zero)

    private var slider: UISlider? {
        volumeView.subviews.first { $0 is UISlider } as? UISlider
    }

    func install() {
        guard volumeView.superview == nil else { return }
        volumeView.frame = CGRect(x: -2000, y: -2000, width: 1, height: 1)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.addSubview(volumeView)
    }

    func setVolume(_ value: Float) {
        slider?.value = value
    }
}
