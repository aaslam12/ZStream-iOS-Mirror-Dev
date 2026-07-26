//
//  CustomScrubber.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI

struct CustomScrubber: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double, @escaping () -> Void) -> Void
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var startProgress: Double = 0
    @State private var referenceTranslation: CGFloat = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : min(currentTime / duration, 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * progress)
            }
            .frame(height: isDragging ? 10 : 6)
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .modifier(ScrubberHousing())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            // Capture the pre-drag position BEFORE flipping
                            // isDragging: `progress` reads `dragProgress` once
                            // isDragging is true, which still held last drag's
                            // stale value (0 on the very first drag) — order
                            // matters here.
                            startProgress = progress
                            dragProgress = startProgress
                            isDragging = true
                            referenceTranslation = value.translation.width
                            onScrubbingChanged(true)
                        }
                        let adjustedTranslation = value.translation.width - referenceTranslation
                        let delta = Double(adjustedTranslation / geo.size.width)
                        dragProgress = min(max(startProgress + delta, 0), 1)
                    }
                    .onEnded { _ in
                        let target = dragProgress * duration
                        onSeek(target) {
                            isDragging = false
                            onScrubbingChanged(false)
                        }
                    }
            )
        }
        .frame(height: 32)
    }
}

private struct ScrubberHousing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
    }
}
