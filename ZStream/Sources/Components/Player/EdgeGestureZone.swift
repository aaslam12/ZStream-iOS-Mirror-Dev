//
//  EdgeGestureZone.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI
import AVFoundation

struct EdgeGestureZone: View {
    enum Kind {
        case brightness, volume

        var iconRamp: [String] {
            switch self {
            case .brightness:
                return ["moon.fill", "sun.min.fill", "sun.max.fill"]
            case .volume:
                return ["speaker.slash.fill", "speaker.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill"]
            }
        }

        func icon(for value: Double) -> String {
            let clamped = min(max(value, 0), 1)
            if clamped == 0 { return iconRamp.first ?? "questionmark" }
            let bucket = Int(ceil(clamped * Double(iconRamp.count - 1)))
            return iconRamp[min(bucket, iconRamp.count - 1)]
        }
    }

    let kind: Kind
    var debugVisible: Bool = true

    @StateObject private var volumeObserver = VolumeObserver()
    @State private var value: Double = 0
    @State private var startValue: Double = 0
    @State private var referenceTranslation: CGFloat = 0
    @State private var isActive = false
    @State private var isDragging = false
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        Rectangle()
            .fill(debugVisible ? Color.red.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            isActive = true
                            startValue = currentSystemValue()
                            referenceTranslation = drag.translation.height
                            hideWorkItem?.cancel()
                        }
                        let adjustedTranslation = drag.translation.height - referenceTranslation
                        let delta = Double(-adjustedTranslation / 200)
                        value = min(max(startValue + delta, 0), 1)
                        apply(value)
                    }
                    .onEnded { _ in
                        isDragging = false
                        scheduleHide()
                    }
            )
            .overlay {
                if isActive {
                    VerticalGestureBar(icon: kind.icon(for: value), value: value)
                }
            }
            .onAppear {
                value = currentSystemValue()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
                guard kind == .brightness, !isDragging else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    value = currentSystemValue()
                }
                isActive = true
                hideWorkItem?.cancel()
                scheduleHide()
            }
            .onChange(of: volumeObserver.outputVolume) { _, newValue in
                guard kind == .volume, !isDragging else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    value = Double(newValue)
                }
                isActive = true
                hideWorkItem?.cancel()
                scheduleHide()
            }
    }

    private func scheduleHide() {
        let work = DispatchWorkItem { isActive = false }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func currentSystemValue() -> Double {
        switch kind {
        case .brightness: return UIScreen.main.brightness
        case .volume: return Double(AVAudioSession.sharedInstance().outputVolume)
        }
    }

    private func apply(_ newValue: Double) {
        switch kind {
        case .brightness: UIScreen.main.brightness = newValue
        case .volume: SystemVolumeController.shared.setVolume(Float(newValue))
        }
    }
}
