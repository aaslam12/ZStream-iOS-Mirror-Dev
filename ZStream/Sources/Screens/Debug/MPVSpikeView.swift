//
//  MPVSpikeView.swift
//  ZStream
//
//  Phase 0 spike (see AVPlayer→mpv migration plan): plays a raw stream URL
//  directly through libmpv, bypassing PlaybackSource/HLSPlaybackProxy/
//  PlayerViewModel entirely, to prove mpv can demux disguised segments with
//  custom headers and decode 4K HDR HEVC without hitting AVPlayer's
//  CoreMediaErrorDomain -12927. Reached only from VideoTesterView.
//

import SwiftUI

struct MPVSpikeView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let headers: [String: String]?

    @State private var client = MinimalMPVClient()
    @State private var errorText: String?
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MinimalMPVRenderView(client: client)
                .onAppear {
                    guard !started else { return }
                    started = true
                    do {
                        try client.start(url: url, headers: headers)
                        client.play()
                    } catch {
                        errorText = "\(error)"
                    }
                }
            VStack {
                HStack {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                        .padding()
                    Spacer()
                }
                Spacer()
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote.monospaced())
                        .padding()
                        .background(.black.opacity(0.6))
                }
            }
        }
        .onDisappear { client.stop() }
    }
}
