//
//  AboutFAQView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct AboutFAQView: View {
    @State private var hasAppeared = false
    @State private var secretTaps = 0
    @State private var showVideoTester = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AppLogoBadge()
                        .scaleEffect(1.1)
                        .padding(.top, 8)
                        .contentShape(Rectangle())
                        // simultaneousGesture so it fires alongside the badge's
                        // own press animation on older iOS (which would otherwise
                        // swallow a plain onTapGesture).
                        .simultaneousGesture(TapGesture().onEnded { registerSecretTap() })

                    Text("Version \(appVersion) (.\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .opacity(hasAppeared ? 1 : 0)
                        .animation(.easeIn(duration: 0.4).delay(0.3), value: hasAppeared)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)

            Section("About") {
                aboutRow(icon: "sparkles", title: "What is ZStream?", detail: "ZStream is an open-source media companion app for browsing, watching, and organizing movies and tv shows.", index: 0)
                aboutRow(icon: "lock.shield", title: "Your Data", detail: "ZStream connects to a backend you choose. Your account and activity live on that backend, not with any single entity.", index: 1)
                aboutRow(icon: "chevron.left.slash.chevron.right", title: "Open Source", detail: "ZStream's source is fully open — anyone can inspect, modify, or self-host it.", index: 2)
            }

            Section("Legal") {
                NavigationLink("Open Source") { OpenSourceInfoView() }
                NavigationLink("Code of Conduct") { CodeOfConductView() }
                NavigationLink("License") { LicenseView() }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("About & FAQ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasAppeared = true
        }
        .fullScreenCover(isPresented: $showVideoTester) {
            VideoTesterView()
        }
    }

    /// Hidden developer entry point: tap the Z-Stream badge 5 times to open the
    /// video-player tester.
    private func registerSecretTap() {
        secretTaps += 1
        if secretTaps >= 5 {
            secretTaps = 0
            showVideoTester = true
        }
    }

    private func aboutRow(icon: String, title: String, detail: String, index: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -12)
        .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.08), value: hasAppeared)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - Video tester (hidden dev tool)

/// Reached via the About & FAQ easter egg. Plays an arbitrary stream URL through
/// the native player (proxy off, so standard MP4/HLS aren't re-typed), with
/// optional request headers and a couple of hardcoded preset streams.
struct VideoTesterView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var format: StreamFormat = .hls
    @State private var headersEnabled = false
    @State private var headerRows: [HeaderRow] = []
    @State private var playback: TesterPlayback?
    @State private var invalidURL = false

    private static let hlsTestURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
    private static let mp4TestURL = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4"

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom stream") {
                    TextField("https://…", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Picker("Format", selection: $format) {
                        ForEach(StreamFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Headers", isOn: $headersEnabled.animation())

                    if headersEnabled {
                        ForEach($headerRows) { $row in
                            HStack(spacing: 8) {
                                TextField("Name", text: $row.name)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                Divider()
                                TextField("Value", text: $row.value)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                        .onDelete { headerRows.remove(atOffsets: $0) }

                        Button {
                            headerRows.append(HeaderRow())
                        } label: {
                            Label("Add header", systemImage: "plus.circle")
                        }
                    }
                }

                Section {
                    Button {
                        start(urlString: urlText)
                    } label: {
                        Text("Start stream")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Preset tests") {
                    Button("HLS test") { start(urlString: Self.hlsTestURL) }
                    Button("MP4 test") { start(urlString: Self.mp4TestURL) }
                }
            }
            .navigationTitle("Video tester")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Invalid URL", isPresented: $invalidURL) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enter a valid absolute URL (including https://).")
            }
            .fullScreenCover(item: $playback) { item in
                PlayerView(source: item.source, reference: item.reference)
            }
        }
    }

    private func start(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            invalidURL = true
            return
        }

        var headers: [String: String]? = nil
        if headersEnabled {
            let pairs = headerRows
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.name, $0.value) }
            if !pairs.isEmpty { headers = Dictionary(pairs, uniquingKeysWith: { _, last in last }) }
        }

        playback = TesterPlayback(
            source: PlaybackSource(url: url, headers: headers, useProxy: false),
            reference: MediaItemReference(mediaId: 0, mediaType: .movie)
        )
    }

    enum StreamFormat: String, CaseIterable, Identifiable {
        case mp4, hls, mkv
        var id: String { rawValue }
        var label: String {
            switch self {
            case .mp4: return "MP4"
            case .hls: return "HLS"
            case .mkv: return "MKV"
            }
        }
    }

    struct HeaderRow: Identifiable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    struct TesterPlayback: Identifiable {
        let id = UUID()
        let source: PlaybackSource
        let reference: MediaItemReference
    }
}
