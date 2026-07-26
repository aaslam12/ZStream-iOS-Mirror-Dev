//
//  VolumeObserver.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import AVFoundation
import Combine

@MainActor
final class VolumeObserver: ObservableObject {
    @Published private(set) var outputVolume: Float
    private var observation: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        outputVolume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            DispatchQueue.main.async {
                self?.outputVolume = newValue
            }
        }
    }

    deinit {
        observation?.invalidate()
    }
}
