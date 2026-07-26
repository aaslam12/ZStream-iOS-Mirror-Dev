//
//  MinimalMPVRenderView.swift
//  ZStream
//
//  Drives MinimalMPVClient's software render loop into a plain UIImageView
//  via CADisplayLink. Deliberately simple/low-performance — this spike only
//  needs to prove mpv demuxes/decodes, not that it's smooth.
//

import SwiftUI
import UIKit

final class MinimalMPVRenderUIView: UIView {
    let client: MinimalMPVClient
    private let imageView = UIImageView()
    private var displayLink: CADisplayLink?

    init(client: MinimalMPVClient) {
        self.client = client
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 24
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    deinit { displayLink?.invalidate() }

    @objc private func tick() {
        client.pollEvents()
        let width = max(Int(bounds.width * UIScreen.main.scale), 2)
        let height = max(Int(bounds.height * UIScreen.main.scale), 2)
        guard width > 1, height > 1,
              let (bytes, bytesPerRow) = client.renderFrame(width: width, height: height) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return }

        imageView.image = UIImage(cgImage: cgImage)
    }
}

struct MinimalMPVRenderView: UIViewRepresentable {
    let client: MinimalMPVClient

    func makeUIView(context: Context) -> MinimalMPVRenderUIView {
        MinimalMPVRenderUIView(client: client)
    }

    func updateUIView(_ uiView: MinimalMPVRenderUIView, context: Context) {}
}
