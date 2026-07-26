//
//  PlayerControlsOverlay.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI
import ZStreamCore

struct PlayerControlsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isVisible: Bool

    /// All sources the user can switch playback to, the id of whichever one
    /// is currently playing (nil if unknown), and whether a switch is in
    /// flight (drives a spinner in place of the source button's icon).
    var sources: [SourceInfo] = []
    var currentSourceId: String?
    var isSwitchingSource: Bool = false
    var onSelectSource: (SourceInfo) -> Void = { _ in }

    var onScrubbingChanged: (Bool) -> Void = { _ in }
    var onMenuVisibilityChanged: (Bool) -> Void = { _ in }
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if isVisible {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)

                centerControls
                    .transition(.opacity)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.5), in: Circle())
            }
            Spacer()
        }
        .padding(16)
    }

    private var centerControls: some View {
        HStack(spacing: 40) {
            skipButton(amount: -10)
            pauseButton()
            skipButton(amount: 10)
        }
    }

    @ViewBuilder
    private func skipButton(amount: Double) -> some View {
        if #available(iOS 26.0, *) {
            Button {
                viewModel.skip(by: amount)
            } label: {
                Image(systemName: amount < 0 ? "gobackward.10" : "goforward.10")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.white)
        } else {
            Button {
                viewModel.skip(by: amount)
            } label: {
                Image(systemName: amount < 0 ? "gobackward.10" : "goforward.10")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .padding(10)
            }
            .background(.ultraThinMaterial, in: .circle)
        }
    }

    @ViewBuilder
    private func pauseButton() -> some View {
        if #available(iOS 26.0, *) {
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.white)
        } else {
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .padding(10)
            }
            .background(.ultraThinMaterial, in: .circle)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Spacer()
                // Hidden entirely (not just disabled) when there's nothing to
                // switch to — offline/downloaded playback has no other source.
                if !sources.isEmpty {
                    sourceMenu
                }
                settingsMenu
            }

            HStack {
                Text(timeString(viewModel.currentTime))
                Spacer()
                Text(timeString(viewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))

            CustomScrubber(
                currentTime: viewModel.currentTime,
                duration: viewModel.duration,
                onSeek: { seconds, completion in
                    viewModel.seek(to: seconds, completion: completion)
                },
                onScrubbingChanged: onScrubbingChanged
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    // MARK: - Settings menu (captions / speed / audio / quality)

    // Isolated into its own Equatable view so the ~4Hz currentTime ticks that
    // re-render the overlay don't rebuild the (possibly open) menu — rebuilding
    // a presented menu makes its text flash / "reload".
    private var settingsMenu: some View {
        SettingsMenu(
            subtitleTracks: viewModel.subtitleTracks,
            selectedSubtitleID: viewModel.selectedSubtitleID,
            embeddedSubtitles: viewModel.embeddedSubtitles,
            selectedEmbeddedSubtitleID: viewModel.selectedEmbeddedSubtitleID,
            playbackSpeed: viewModel.playbackSpeed,
            audioTracks: viewModel.audioTracks,
            selectedAudioID: viewModel.selectedAudioID,
            qualities: viewModel.qualities,
            selectedQuality: viewModel.selectedQuality,
            onSelectSubtitle: { viewModel.selectSubtitle($0) },
            onSelectEmbeddedSubtitle: { viewModel.selectEmbeddedSubtitle($0) },
            onSetSpeed: { viewModel.setPlaybackSpeed($0) },
            onSelectAudio: { viewModel.selectAudio($0) },
            onSelectQuality: { viewModel.selectQuality($0) },
            onVisibilityChanged: onMenuVisibilityChanged
        )
        .equatable()
    }

    // MARK: - Source menu (switch which provider the stream plays from)

    // Same Equatable isolation as settingsMenu, and for the same reason: this
    // sits next to it and would otherwise flash/rebuild on every currentTime tick.
    private var sourceMenu: some View {
        SourceMenu(
            sources: sources,
            currentSourceId: currentSourceId,
            isSwitching: isSwitchingSource,
            onSelect: onSelectSource,
            onVisibilityChanged: onMenuVisibilityChanged
        )
        .equatable()
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Settings menu

/// The player's settings menu (captions / speed / audio / quality).
///
/// Deliberately does NOT observe `PlayerViewModel`; it takes plain snapshots of
/// the track state and reports actions through closures. Combined with
/// `.equatable()`, this stops the frequent `currentTime` updates from rebuilding
/// the menu while it's open (which caused the visible text to flash/reload).
private struct SettingsMenu: View, Equatable {
    let subtitleTracks: [PlaybackSubtitle]
    let selectedSubtitleID: UUID?
    let embeddedSubtitles: [PlayerEmbeddedSubtitle]
    let selectedEmbeddedSubtitleID: String?
    let playbackSpeed: Float
    let audioTracks: [PlayerAudioOption]
    let selectedAudioID: String?
    let qualities: [PlayerQuality]
    let selectedQuality: PlayerQuality.Level

    let onSelectSubtitle: (UUID?) -> Void
    let onSelectEmbeddedSubtitle: (String?) -> Void
    let onSetSpeed: (Float) -> Void
    let onSelectAudio: (String) -> Void
    let onSelectQuality: (PlayerQuality.Level) -> Void
    let onVisibilityChanged: (Bool) -> Void

    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0]

    /// Equality ignores the action closures — only the displayed state matters,
    /// so identical snapshots skip a re-render even though new closures are
    /// captured on every parent update.
    static func == (lhs: SettingsMenu, rhs: SettingsMenu) -> Bool {
        lhs.subtitleTracks == rhs.subtitleTracks &&
        lhs.selectedSubtitleID == rhs.selectedSubtitleID &&
        lhs.embeddedSubtitles == rhs.embeddedSubtitles &&
        lhs.selectedEmbeddedSubtitleID == rhs.selectedEmbeddedSubtitleID &&
        lhs.playbackSpeed == rhs.playbackSpeed &&
        lhs.audioTracks == rhs.audioTracks &&
        lhs.selectedAudioID == rhs.selectedAudioID &&
        lhs.qualities == rhs.qualities &&
        lhs.selectedQuality == rhs.selectedQuality
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Menu { menuContent } label: { icon }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.white)
                .menuOrder(.fixed)
        } else {
            Menu { menuContent } label: { icon.background(.ultraThinMaterial, in: .circle) }
                .menuOrder(.fixed)
        }
    }

    // Keep the controls pinned open while the menu is presented — the
    // menu lives inside the overlay, so an auto-hide would dismiss it
    // mid-interaction (same reason we pin during scrubbing).
    private var menuContent: some View {
        Group {
            captionsMenu
            speedMenu
            audioMenu
            qualityMenu
        }
        .onAppear { onVisibilityChanged(true) }
        .onDisappear { onVisibilityChanged(false) }
    }

    private var icon: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(10)
    }

    private var captionsMenu: some View {
        Menu {
            menuChoice(title: "Off", isSelected: selectedSubtitleID == nil && selectedEmbeddedSubtitleID == nil) {
                onSelectSubtitle(nil)
            }
            // External VTT tracks (rendered by the app's own overlay).
            ForEach(subtitleTracks) { track in
                menuChoice(title: track.label, isSelected: selectedSubtitleID == track.id) {
                    onSelectSubtitle(track.id)
                }
            }
            // Subtitle tracks embedded in the stream (rendered by AVPlayer).
            ForEach(embeddedSubtitles) { track in
                menuChoice(title: track.label, isSelected: selectedEmbeddedSubtitleID == track.id) {
                    onSelectEmbeddedSubtitle(track.id)
                }
            }
        } label: {
            Label("Captions", systemImage: "captions.bubble")
        }
        .disabled(subtitleTracks.isEmpty && embeddedSubtitles.isEmpty)
    }

    private var speedMenu: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                menuChoice(title: speedLabel(speed), isSelected: playbackSpeed == speed) {
                    onSetSpeed(speed)
                }
            }
        } label: {
            Label("Speed (\(speedLabel(playbackSpeed)))", systemImage: "speedometer")
        }
    }

    private var audioMenu: some View {
        Menu {
            ForEach(audioTracks) { track in
                menuChoice(title: track.label, isSelected: selectedAudioID == track.id) {
                    onSelectAudio(track.id)
                }
            }
        } label: {
            Label("Audio", systemImage: "waveform")
        }
        .disabled(audioTracks.count < 2)
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(qualities) { quality in
                Button {
                    onSelectQuality(quality.level)
                } label: {
                    if selectedQuality == quality.level {
                        Label(quality.level.rawValue, systemImage: "checkmark")
                    } else {
                        Text(quality.level.rawValue)
                    }
                }
                .disabled(!quality.available)
            }
        } label: {
            Label("Quality", systemImage: "4k.tv")
        }
        .disabled(qualities.isEmpty)
    }

    @ViewBuilder
    private func menuChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == speed.rounded() ? "\(Int(speed))x" : String(format: "%gx", speed)
    }
}

// MARK: - Source menu

/// Lists the providers playback can come from (see `AvailableSources.all`)
/// and lets the user switch to a different one mid-playback.
///
/// Same shape as `SettingsMenu` and for the same reason: plain snapshots of
/// state + `.equatable()` so the ~4Hz `currentTime` ticks don't rebuild an
/// open menu underneath the user.
private struct SourceMenu: View, Equatable {
    let sources: [SourceInfo]
    let currentSourceId: String?
    let isSwitching: Bool

    let onSelect: (SourceInfo) -> Void
    let onVisibilityChanged: (Bool) -> Void

    static func == (lhs: SourceMenu, rhs: SourceMenu) -> Bool {
        lhs.sources.map(\.id) == rhs.sources.map(\.id) &&
        lhs.currentSourceId == rhs.currentSourceId &&
        lhs.isSwitching == rhs.isSwitching
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Menu { menuContent } label: { icon }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.white)
                .menuOrder(.fixed)
                .disabled(isSwitching || sources.isEmpty)
        } else {
            Menu { menuContent } label: { icon.background(.ultraThinMaterial, in: .circle) }
                .menuOrder(.fixed)
                .disabled(isSwitching || sources.isEmpty)
        }
    }

    private var menuContent: some View {
        ForEach(sources, id: \.id) { info in
            Button {
                onSelect(info)
            } label: {
                if info.id == currentSourceId {
                    Label(info.displayName, systemImage: "checkmark")
                } else {
                    Text(info.displayName)
                }
            }
        }
        .onAppear { onVisibilityChanged(true) }
        .onDisappear { onVisibilityChanged(false) }
    }

    @ViewBuilder
    private var icon: some View {
        if isSwitching {
            ProgressView()
                .tint(.white)
                .padding(10)
        } else {
            Image(systemName: "server.rack")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
        }
    }
}
