//
//  PlayerView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI
import AVKit
import ZStreamCore

struct PlayerView: View {
    let source: PlaybackSource
    let reference: MediaItemReference
    var episodeState: EpisodePlaybackState = .none
    /// True for a downloaded file playing from disk — there's nothing to
    /// switch away from, so the player hides the source-switching UI entirely
    /// rather than showing a control with nothing useful to do.
    var isOffline: Bool = false

    var body: some View {
        PlayerContent(source: source, reference: reference, episodeState: episodeState, isOffline: isOffline)
    }
}

private struct PlayerContent: View {
    @StateObject private var viewModel: PlayerViewModel
    @ObservedObject private var episodeState: EpisodePlaybackState
    private let reference: MediaItemReference
    private let isOffline: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var controlsVisible = true
    @State private var hideWorkItem: DispatchWorkItem?

    /// Id of the source currently playing (nil until the user picks one —
    /// we don't track which source the initial resolution landed on).
    @State private var currentSourceId: String?
    /// True while a user-initiated source switch is resolving — disables the
    /// source button and swaps its icon for a spinner.
    @State private var isSwitchingSource = false
    /// Non-nil when a source switch fails — drives an alert. Playback of the
    /// previous source is left untouched.
    @State private var sourceSwitchError: String?

    /// The real, currently-playing source (whatever was actually resolved —
    /// real URL + real headers, e.g. Artemis's signed CDN URL + its Origin/
    /// Referer/User-Agent). Kept in sync on every source switch so the mpv
    /// spike button always tests the exact stream the app itself is playing,
    /// never a hand-typed one.
    @State private var currentPlaybackSource: PlaybackSource
    #if DEBUG
    @State private var showMPVSpike = false
    #endif

    init(source: PlaybackSource, reference: MediaItemReference, episodeState: EpisodePlaybackState, isOffline: Bool) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(source: source, reference: reference))
        self.reference = reference
        self.episodeState = episodeState
        self.isOffline = isOffline
        // Pre-check the source the initial resolution actually landed on, so the
        // menu reflects reality before the user ever switches manually.
        _currentSourceId = State(initialValue: source.sourceId)
        _currentPlaybackSource = State(initialValue: source)
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                #if DEBUG
                // Phase 0 mpv-migration spike: replays the exact stream this
                // screen is already playing (real resolved URL + headers,
                // e.g. Artemis's signed CDN URL and its Origin/Referer/UA)
                // through libmpv instead of AVPlayer, so we can tell whether
                // mpv handles what AVPlayer rejects — without hand-typing
                // anything into a separate tester.
                VStack {
                    HStack {
                        Spacer()
                        Button("mpv") { showMPVSpike = true }
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding()
                    }
                    Spacer()
                }
                .zIndex(999)
                #endif
                // Drives PlayerViewModel's clock off SwiftUI's own render-loop
                // scheduling — see the comment on PlayerViewModel.startClock for
                // why this exists instead of a self-registered Timer/DispatchSourceTimer
                // (both were observed to silently never fire in some environments).
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Color.clear
                        .onChange(of: context.date) { _, _ in viewModel.tick() }
                }
                .allowsHitTesting(false)

                Color.black.ignoresSafeArea()
                    .opacity(1 - min(dragOffset / 400, 0.6))

                PlayerLayerView(player: viewModel.player)
                    .ignoresSafeArea()
                    .scaleEffect(1 - min(dragOffset / 2000, 0.15))
                    .offset(y: dragOffset)

                // Brightness/volume drag zones sit BELOW the controls so the
                // play/pause and skip buttons always win the touch when the
                // overlay is visible (the zones only occupy the screen edges,
                // but their hit area otherwise reads before the buttons).
                HStack {
                    EdgeGestureZone(kind: .brightness, debugVisible: false)
                        .frame(width: 90, height: isLandscape ? 150 : 220)
                    Spacer()
                    EdgeGestureZone(kind: .volume, debugVisible: false)
                        .frame(width: 90, height: isLandscape ? 150 : 220)
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)
                .offset(y: isLandscape ? -20 : -40)

                subtitleOverlay
                    .offset(y: dragOffset)
                    .zIndex(2)

                if viewModel.isLoading {
                    ProgressView().tint(.white)
                }

                if let errorMessage = viewModel.errorMessage {
                    errorOverlay(errorMessage)
                } else {
                    PlayerControlsOverlay(
                        viewModel: viewModel,
                        isVisible: $controlsVisible,
                        sources: allSources,
                        currentSourceId: currentSourceId,
                        isSwitchingSource: isSwitchingSource,
                        onSelectSource: { info in
                            Task { await switchSource(to: info) }
                        },
                        onScrubbingChanged: { scrubbing in
                            if scrubbing {
                                hideWorkItem?.cancel()
                            } else {
                                scheduleAutoHide()
                            }
                        },
                        onMenuVisibilityChanged: { menuOpen in
                            if menuOpen {
                                hideWorkItem?.cancel()
                            } else {
                                scheduleAutoHide()
                            }
                        },
                        onClose: { dismissPlayer() }
                    )
                    .offset(y: dragOffset)
                    .zIndex(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
            .gesture(dismissGesture)
        }
        .statusBarHidden()
        .onAppear {
            viewModel.player.play()
            SystemVolumeController.shared.install()
            OrientationManager.shared.allowsLandscape = true
            scheduleAutoHide()
        }
        .onDisappear {
            viewModel.stop()
            OrientationManager.shared.allowsLandscape = false
        }
        .onChange(of: episodeState.currentEpisode?.id) { _, newId in
            guard newId != nil, let episode = episodeState.currentEpisode else { return }
            Task {
                do {
                    let newSource = try await TestStreamCatalog.source(
                        forEpisodeId: episode.id,
                        tmdbId: reference.mediaId,
                        season: episodeState.currentSeasonNumber,
                        episode: episode.episodeNumber
                    )
                    viewModel.replace(with: newSource)
                    currentSourceId = nil
                } catch {
                    viewModel.isLoading = false
                    viewModel.errorMessage = "Couldn't load this episode."
                }
            }
        }
        .onChange(of: viewModel.didFinishPlaying) { _, finished in
            guard finished else { return }
            if episodeState.hasNext {
                episodeState.playNext()
            }
        }
        .alert("Source Unavailable", isPresented: Binding(
            get: { sourceSwitchError != nil },
            set: { if !$0 { sourceSwitchError = nil } }
        )) {
            Button("OK", role: .cancel) { sourceSwitchError = nil }
        } message: {
            Text(sourceSwitchError ?? "")
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showMPVSpike) {
            MPVSpikeView(url: currentPlaybackSource.url, headers: currentPlaybackSource.headers)
        }
        #endif
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismissPlayer()
                } else {
                    withAnimation(.spring()) { dragOffset = 0 }
                }
            }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        hideWorkItem?.cancel()
        if controlsVisible { scheduleAutoHide() }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func dismissPlayer() {
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = UIScreen.main.bounds.height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismiss()
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.white)
            Text(message).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Source switching

    /// Every source the user can pick from, across every registered StreamSource.
    /// Empty for offline playback — there's nothing to switch to, so the
    /// source button hides itself entirely (see PlayerControlsOverlay).
    private var allSources: [SourceInfo] {
        isOffline ? [] : AvailableSources.all.flatMap { $0.availableSources() }
    }

    /// What's currently playing, described the way `StreamSource.resolve` needs it.
    private var currentMediaRequest: MediaRequest {
        if reference.mediaType == .movie {
            return MediaRequest(type: .movie, tmdbId: String(reference.mediaId))
        }
        return MediaRequest(
            type: .show,
            tmdbId: String(reference.mediaId),
            season: episodeState.currentSeasonNumber,
            episode: episodeState.currentEpisode?.episodeNumber
        )
    }

    /// Resolves `info` directly (not through `SourceResolver`'s fallback chain —
    /// the user picked this one specifically) and swaps playback to it on success.
    /// Leaves the current stream playing untouched on failure.
    private func switchSource(to info: SourceInfo) async {
        guard let streamSource = AvailableSources.all.first(where: { source in
            source.availableSources().contains { $0.id == info.id }
        }) else { return }

        isSwitchingSource = true
        defer { isSwitchingSource = false }

        print("[Sources] user switching to \(info.id)…")
        switch await streamSource.resolve(media: currentMediaRequest, sourceId: info.id) {
        case .success(let success):
            guard let url = URL(string: success.streamUrl) else {
                sourceSwitchError = "This source returned an invalid stream."
                return
            }
            print("[Sources] ✔ switch to \(info.id) resolved — host=\(url.host ?? "?") captions=\(success.captions.count)")
            let newSource = PlaybackSource(
                url: url,
                headers: success.headers,
                subtitles: success.captions.compactMap { caption in
                    guard let subtitleURL = URL(string: caption.url) else { return nil }
                    return PlaybackSubtitle(label: caption.language, url: subtitleURL)
                },
                sourceId: info.id
            )
            viewModel.replace(with: newSource)
            currentSourceId = info.id
            currentPlaybackSource = newSource
        case .notFound:
            print("[Sources] ✘ switch to \(info.id): no stream for this title")
            sourceSwitchError = "\(info.displayName) doesn't have this title available."
        case .error(let message):
            print("[Sources] ✘ switch to \(info.id) failed: \(message)")
            sourceSwitchError = "\(info.displayName) doesn't have this title available."
        }
    }

    /// App-rendered captions (AVPlayer can't ingest the standalone VTT URLs).
    /// Lifts above the controls while they're visible.
    @ViewBuilder
    private var subtitleOverlay: some View {
        if let text = viewModel.currentSubtitleText, !text.isEmpty {
            VStack {
                Spacer()
                Text(text)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 24)
                    .padding(.bottom, controlsVisible ? 150 : 60)
                    .animation(.easeInOut(duration: 0.2), value: controlsVisible)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
