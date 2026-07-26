//
//  SplashScreen.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/22/26.
//

import SwiftUI
import ImageIO
import UIKit

struct SplashView: View {
    @State private var barWidth: CGFloat = 6
    @State private var barHeight: CGFloat = 6
    @State private var lineOpacity: Double = 0
    @State private var trailOpacity: Double = 0
    
    private let logoSize: CGFloat = 100
    private let lineColor = Color(red: 0.93, green: 0.94, blue: 0.95)
    private let trailLength: CGFloat = 30
    
    var onFinished: () -> Void

    var body: some View {
        // If a splash GIF is bundled (Resources/splash.gif), play it; otherwise
        // fall back to the built-in beam animation. This keeps the current splash
        // intact until an actual GIF is added to the target.
        if let gif = Self.splashGIF {
            gifSplash(gif)
        } else {
            beamSplash
        }
    }

    // MARK: - GIF splash

    /// Bundled GIF data + total duration, resolved once. Add `splash.gif` to the
    /// app target's resources to enable this branch.
    private static let splashGIF: (data: Data, duration: Double)? = {
        guard let url = Bundle.main.url(forResource: "splash", withExtension: "gif"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (data, GIFImageView.duration(of: data))
    }()

    private func gifSplash(_ gif: (data: Data, duration: Double)) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GIFImageView(data: gif.data)
                .frame(width: 128, height: 128)
        }
        .onAppear {
            let hold = min(max(gif.duration, 1.0), 4.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                onFinished()
            }
        }
    }

    // MARK: - Built-in beam splash (fallback)

    private var beamSplash: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // The icon, revealed only through the growing rectangle mask.
            Image("Icon")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .mask(
                    Rectangle()
                        .frame(width: barWidth, height: barHeight - 6)
                )
            // Phase 1: dot stretching into a full-width horizontal line.
            Rectangle()
                .fill(lineColor)
                .frame(width: barWidth, height: 4)
                .opacity(lineOpacity)
            // Phase 2: beam traveling upward, tail fading toward center.
            Rectangle()
                .fill(LinearGradient(colors: [lineColor, .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: barWidth, height: trailLength)
                .offset(y: -(barHeight / 2) - trailLength / 2)
                .opacity(trailOpacity)
            // Phase 2: beam traveling downward, tail fading toward center.
            Rectangle()
                .fill(LinearGradient(colors: [lineColor, .clear], startPoint: .bottom, endPoint: .top))
                .frame(width: barWidth, height: trailLength)
                .offset(y: (barHeight / 2) + trailLength / 2)
                .opacity(trailOpacity)
        }
        .onAppear(perform: runAnimation)
    }
    
    private func runAnimation() {
        let screen = UIScreen.main.bounds.size
        // Dot fades in at the center.
        withAnimation(.easeOut(duration: 0.08)) {
            lineOpacity = 1
        }
        // Dot stretches into a line spanning the full screen width.
        withAnimation(.easeOut(duration: 0.24).delay(0.08)) {
            barWidth = screen.width
        }
        // Handoff: the solid line fades as the two trailing beams appear.
        withAnimation(.easeOut(duration: 0.1).delay(0.28)) {
            lineOpacity = 0
            trailOpacity = 1
        }
        // The two beams peel apart to the top and bottom edges, each
        // dragging its own fixed-length trail — no full-screen flash.
        withAnimation(.easeInOut(duration: 0.42).delay(0.32)) {
            barHeight = screen.height
        }
        // Trails fade out once the icon is fully revealed.
        withAnimation(.easeOut(duration: 0.15).delay(0.74)) {
            trailOpacity = 0
        }
        // Hand off to the app after a short hold (~950ms total).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            onFinished()
        }
    }
}

// MARK: - GIF rendering

/// Plays an animated GIF from raw data via a UIImageView (no dependencies).
struct GIFImageView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        
        // Allow SwiftUI to shrink the view smaller than the GIF's actual pixel size
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.image = Self.animatedImage(from: data)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    /// Total playback duration of the GIF, in seconds.
    static func duration(of data: Data) -> Double {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 1.0 }
        let count = CGImageSourceGetCount(source)
        return (0..<count).reduce(0.0) { $0 + frameDelay(source, $1) }
    }

    private static func animatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var total = 0.0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            total += frameDelay(source, index)
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: total)
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        // GIFs with sub-20ms frames are typically meant to run at ~10fps.
        return delay < 0.02 ? 0.1 : delay
    }
}
