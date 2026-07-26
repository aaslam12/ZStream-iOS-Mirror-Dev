//
//  MediaItemDialog.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//
//  The full-screen sheet shown when tapping any movie/show poster —
//  displays hero art, play/bookmark/download controls, metadata, cast
//  or episodes depending on media type, and similar-title suggestions.
//

import SwiftUI
import ZStreamCore

struct MediaItemDialog: View {

    // MARK: - Inputs

    /// Which movie/show this dialog is showing, and whether it's a movie or TV show.
    let reference: MediaItemReference

    /// Called when the user taps a "Similar" item — lets the parent screen
    /// swap this same sheet to show a different title instead of stacking a
    /// second sheet on top.
    var onNavigate: (MediaItemReference) -> Void

    // MARK: - Environment (shared app-wide state)

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var contentStore: ContentStore
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local state

    /// Owns all the network-fetched data for this specific title (detail,
    /// credits, external links, episodes for the currently selected season).
    @StateObject private var state: MediaItemDetailState

    /// Set the moment the user taps Play/Resume/an episode — presenting this
    /// (via .fullScreenCover(item:)) is what actually opens the player.
    @State private var playbackRequest: PlaybackRequest?

    /// Phase 0 mpv-migration spike: set when the user taps "Play with mpv" —
    /// resolves a real source exactly like normal Play does, then opens it
    /// through libmpv instead of AVPlayer/PlayerView.
    @State private var mpvPlaybackRequest: MPVPlaybackRequest?
    /// True right after a long-press on Play/Resume — asks which player to use.
    @State private var showPlayerChoice = false

    /// True for ~2.5s right after a download finishes, so the more-menu
    /// button briefly shows a green checkmark before reverting to "...".
    @State private var showCompletedBriefly = false

    /// Non-nil when resolving/starting playback failed — drives an error alert.
    @State private var playbackError: String?

    /// Playback resolution takes ~1s; these drive spinners so the tap gives
    /// immediate feedback. `loadingEpisodeId` marks the specific episode card;
    /// `isResolvingPlayback` marks the main Play/Resume button.
    @State private var loadingEpisodeId: Int?
    @State private var isResolvingPlayback = false

    /// Non-nil while SourceResolver is working through AvailableSources.all
    /// for the main playback flow — drives the full-screen per-source status
    /// overlay nil again the moment resolution finishes, success or failure,
    /// so it never overlaps with the PlayerView fullScreenCover.
    @State private var resolvingSources: [SourceResult]?

    /// True once every source has been tried (or the user's single manually-picked
    /// source failed) and none had this title — drives the "no source" full-screen
    /// state in place of the generic playback-error alert.
    @State private var noSourceAvailable = false

    /// Non-nil while `AppSettings.manualSourceSelection` is on and playback is
    /// starting — presents a sheet asking which source to use, and resumes the
    /// awaiting resolvePlaybackSource() call with the user's pick (or nil on cancel).
    @State private var manualSourcePickRequest: ManualSourcePickRequest?

    /// Non-nil right after a source has been resolved for a download and
    /// we're waiting on the user to pick a quality — presents the picker
    /// sheet, which does its own async variant lookup once shown.
    @State private var pendingQualityDownload: PendingQualityDownload?

    init(reference: MediaItemReference, settings: AppSettings, onNavigate: @escaping (MediaItemReference) -> Void) {
        self.reference = reference
        self.onNavigate = onNavigate
        _state = StateObject(wrappedValue: MediaItemDetailState(reference: reference, settings: settings))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                buttonRow.padding(.horizontal)
                overviewSection.padding(.horizontal)
                infoPanel.padding(.horizontal)

                switch reference.mediaType {
                case .movie: castSection
                case .tv: episodesSection
                }

                similarSection
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .task {
            // Fires once when the dialog first appears — loads detail,
            // credits, external IDs, and (for TV) the first season's episodes.
            await state.load()
        }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(source: request.source, reference: reference, episodeState: request.episodeState)
        }
        .fullScreenCover(item: $mpvPlaybackRequest) { request in
            MPVSpikeView(url: request.url, headers: request.headers)
        }
        .confirmationDialog("Play with…", isPresented: $showPlayerChoice, titleVisibility: .visible) {
            Button("AVPlayer") { Task { await startPlayback() } }
            Button("mpv (Phase 0 spike)") { Task { await startPlayback(openInMPV: true) } }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: Binding(
            get: { resolvingSources != nil },
            set: { if !$0 { resolvingSources = nil } }
        )) {
            SourceResolutionOverlay(sources: resolvingSources ?? [], onCancel: { resolvingSources = nil })
        }
        .fullScreenCover(isPresented: $noSourceAvailable) {
            NoSourceAvailableView(onDismiss: {
                noSourceAvailable = false
                dismiss()
            })
        }
        .sheet(item: $manualSourcePickRequest) { request in
            SourcePickerSheet(
                candidates: request.candidates,
                accentColor: settings.theme.accent,
                onSelect: request.onSelect
            )
        }
        .alert("Playback Unavailable", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) { playbackError = nil }
        } message: {
            Text(playbackError ?? "")
        }
        .sheet(item: $pendingQualityDownload) { request in
            DownloadQualityPickerSheet(
                source: request.source,
                runtimeMinutes: request.runtimeMinutes,
                accentColor: settings.theme.accent,
                onSelect: request.onSelect
            )
        }
    }

    // MARK: - Playback

    private enum SourceResolutionError: Error { case noSource, cancelled }

    /// Resolves a playable stream via the StreamSource pipeline. By default tries
    /// every registered source in the user's preferred order (see
    /// `AvailableSources.orderedCandidates`), promoting the title's last-known-working
    /// source to the front when `AppSettings.prioritizeLastUsedSource` is on.
    ///
    /// `reportProgress` mirrors per-source status into `resolvingSources` so the
    /// overlay can render it; pass `false` for background flows (downloads) that
    /// shouldn't show the full-screen status list.
    ///
    /// `allowManualPick` additionally lets `AppSettings.manualSourceSelection`
    /// intercept resolution with a picker sheet before anything is tried — only
    /// the main "open the player" call sites pass `true`; downloads always resolve
    /// automatically regardless of that setting.
    private func resolvePlaybackSource(media: MediaRequest, reportProgress: Bool = false, allowManualPick: Bool = false) async throws -> PlaybackSource {
        let onUpdate: ([SourceResult]) -> Void = reportProgress
            ? { results in resolvingSources = results }
            : { _ in }

        let candidates: [SourceResolver.Candidate]
        if allowManualPick && settings.manualSourceSelection {
            guard let chosen = await pickSourceManually() else {
                throw SourceResolutionError.cancelled
            }
            candidates = [chosen]
        } else {
            let mediaKey = LastUsedSourceStore.mediaKey(for: media)
            let lastUsedId = settings.prioritizeLastUsedSource
                ? await LastUsedSourceStore.shared.sourceId(for: mediaKey)
                : nil
            candidates = AvailableSources.orderedCandidates(preference: settings.sourceOrder, prioritizing: lastUsedId)
        }

        guard let resolution = await SourceResolver(candidates: candidates).resolve(media: media, onUpdate: onUpdate),
              let url = URL(string: resolution.success.streamUrl) else {
            throw SourceResolutionError.noSource
        }

        await LastUsedSourceStore.shared.record(sourceId: resolution.sourceId, for: LastUsedSourceStore.mediaKey(for: media))

        return PlaybackSource(
            url: url,
            headers: resolution.success.headers,
            subtitles: resolution.success.captions.compactMap { caption in
                guard let subtitleURL = URL(string: caption.url) else { return nil }
                return PlaybackSubtitle(label: caption.language, url: subtitleURL)
            },
            sourceId: resolution.sourceId
        )
    }

    /// Presents `SourcePickerSheet` and suspends until the user picks a source
    /// or dismisses it — returning nil in the latter case.
    private func pickSourceManually() async -> SourceResolver.Candidate? {
        await withCheckedContinuation { continuation in
            manualSourcePickRequest = ManualSourcePickRequest(candidates: AvailableSources.allCandidates()) { chosen in
                continuation.resume(returning: chosen)
            }
        }
    }

    /// Starts playback. For movies, always plays the movie itself.
    /// For TV, plays a specific episode (or the first episode of the
    /// currently selected season if none was specified — e.g. tapping
    /// the main "Play" button rather than a specific episode card).
    /// - Parameter openInMPV: identical resolution/resume/local-file logic to
    ///   the normal path — only what gets presented afterward differs (mpv
    ///   spike instead of the real AVPlayer-backed PlayerView).
    private func startPlayback(episode: SeasonDetail.Episode? = nil, openInMPV: Bool = false) async {
        if let episode {
            loadingEpisodeId = episode.id
        } else {
            isResolvingPlayback = true
        }
        defer {
            loadingEpisodeId = nil
            isResolvingPlayback = false
            resolvingSources = nil
        }
        do {
            switch reference.mediaType {
            case .movie:
                // Prefer the offline copy when present — saves bandwidth and
                // skips stream resolution entirely.
                let source: PlaybackSource
                if let local = localMovieSource() {
                    source = local
                } else {
                    source = try await resolvePlaybackSource(media: MediaRequest(type: .movie, tmdbId: String(reference.mediaId)), reportProgress: true, allowManualPick: true)
                }
                resolvingSources = nil
                if openInMPV {
                    mpvPlaybackRequest = MPVPlaybackRequest(url: source.url, headers: source.headers)
                } else {
                    playbackRequest = PlaybackRequest(source: source, episodeState: .none)
                }

            case .tv:
                guard let startEpisode = episode ?? state.seasonEpisodes.first else { return }
                let newEpisodeState = EpisodePlaybackState(
                    seasonNumber: state.selectedSeason,
                    episodes: state.seasonEpisodes,
                    startingAt: startEpisode
                )

                let source: PlaybackSource
                if let local = localEpisodeSource(startEpisode) {
                    source = local
                } else {
                    source = try await resolvePlaybackSource(media: MediaRequest(
                        type: .show,
                        tmdbId: String(reference.mediaId),
                        season: state.selectedSeason,
                        episode: startEpisode.episodeNumber
                    ), reportProgress: true, allowManualPick: true)
                }

                resolvingSources = nil
                if openInMPV {
                    mpvPlaybackRequest = MPVPlaybackRequest(url: source.url, headers: source.headers)
                } else {
                    playbackRequest = PlaybackRequest(source: source, episodeState: newEpisodeState)
                }
            }
        } catch SourceResolutionError.cancelled {
            // User backed out of the manual source picker — nothing to show.
        } catch SourceResolutionError.noSource {
            noSourceAvailable = true
        } catch {
            print("Playback failed:", error)
            playbackError = "Couldn't start playback. This title may be unavailable."
        }
    }

    /// Local playback source for this movie if it's been downloaded, else nil.
    private func localMovieSource() -> PlaybackSource? {
        guard let record = downloadManager.completedDownloads.first(where: { $0.id == downloadIdentifier }) else {
            return nil
        }
        return PlaybackSource(url: record.resolvedFileURL)
    }

    /// Local playback source for a downloaded episode if present, else nil.
    private func localEpisodeSource(_ episode: SeasonDetail.Episode) -> PlaybackSource? {
        guard let record = downloadManager.completedDownloads.first(where: { $0.id == episodeDownloadId(episode) }) else {
            return nil
        }
        return PlaybackSource(url: record.resolvedFileURL)
    }

    // MARK: - Hero (backdrop image + title + rating/year/season count)

    private var heroSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                FadeInImage(url: backdropURL)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                    .frame(width: geo.size.width, height: geo.size.height)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    metaRow
                }
                .padding(20)
            }
        }
        .frame(height: 340)
    }

    /// Rating (or "No Ratings"), release year, and — for TV only — season count.
    private var metaRow: some View {
        HStack(spacing: 6) {
            if hasRatings {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(String(format: "%.1f", voteAverage))
                Text("(\(voteCount))").foregroundStyle(.white.opacity(0.7))
            } else {
                Image(systemName: "star.slash").foregroundStyle(.white.opacity(0.6))
                Text("No Ratings")
            }

            if let year = releaseYear {
                Text("•")
                Text(String(year))
            }

            if reference.mediaType == .tv, let seasons = state.tvDetail?.numberOfSeasons {
                Text("•")
                Text("\(seasons) Season\(seasons == 1 ? "" : "s")")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
    }

    // MARK: - Button row (Play/Resume, Bookmark, More menu)
    //
    // Every button here has a version-gated pair: iOS 26+ uses real Liquid
    // Glass (.buttonStyle(.glass) / .glassProminent), older iOS falls back
    // to plain .bordered / .borderedProminent. This is the pattern repeated
    // throughout the file — look for "if #available(iOS 26.0, *)".

    @ViewBuilder
    private var buttonRow: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 12) {
                playResumeButton

                // Bookmark and the More menu share a GlassEffectContainer so
                // they can visually merge into one shape when close together.
                GlassEffectContainer(spacing: 12) {
                    bookmarkButton
                }

                moreMenu
            }
        } else {
            HStack(spacing: 12) {
                playResumeButton
                bookmarkButton
                moreMenu
            }
        }
    }

    /// The primary "Play" / "Resume" / "Unreleased" / "Notify Me" button.
    ///
    /// Phase 0 mpv-migration spike: long-press asks which player to use
    /// instead of a separate button — a normal tap always behaves exactly
    /// as before (AVPlayer).
    @ViewBuilder
    private var playResumeButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                Task {
                    await startPlayback()
                }
            } label: {
                playButtonLabelView
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.automatic)
            .tint(isUnreleased ? .gray : settings.theme.accent)
            .disabled(!isDetailLoaded || isUnreleased || isResolvingPlayback)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                showPlayerChoice = true
            })
        } else {
            Button {
                Task {
                    await startPlayback()
                }
            } label: {
                playButtonLabelView
            }
            .buttonStyle(.borderedProminent)
            .tint(isUnreleased ? .gray : settings.theme.accent)
            .disabled(!isDetailLoaded || isUnreleased || isResolvingPlayback)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                showPlayerChoice = true
            })
        }
    }

    /// The Play button's content — swaps in a spinner while playback resolves.
    @ViewBuilder
    private var playButtonLabelView: some View {
        Group {
            if isResolvingPlayback {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Loading…")
                }
            } else {
                Label(playButtonLabel, systemImage: isUnreleased ? "clock" : "play.fill")
            }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Toggles whether this title is bookmarked.
    @ViewBuilder
    private var bookmarkButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                toggleBookmark()
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
        } else {
            Button {
                toggleBookmark()
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    /// True if this title is bookmarked, read straight from `ContentStore` —
    /// the same in-memory list Home's Bookmarks row renders from, loaded once
    /// at launch and kept in sync locally. Previously this was tracked in a
    /// separate `@Published` on `MediaItemDetailState`, refetched over the
    /// network (with a `ttl` of 0, forcing a request) every time the dialog
    /// opened; a stale/slow server response could silently overwrite the local
    /// cache and un-bookmark something that was, in fact, still bookmarked.
    /// Reading the already-loaded local list sidesteps that entirely.
    private var isBookmarked: Bool {
        contentStore.bookmarks.contains { $0.id == reference.mediaId && $0.mediaType == reference.mediaType }
    }

    /// Flips the bookmark instantly (no waiting on the network call) by
    /// mutating `ContentStore` directly, then persists in the background.
    private func toggleBookmark() {
        if isBookmarked {
            contentStore.bookmarks.removeAll { $0.id == reference.mediaId && $0.mediaType == reference.mediaType }
            Task { await BookmarksRepository().remove(id: reference.mediaId, mediaType: reference.mediaType) }
        } else {
            contentStore.bookmarks.append(Bookmark(id: reference.mediaId, mediaType: reference.mediaType, addedAt: Date()))
            Task { await BookmarksRepository().add(Bookmark(id: reference.mediaId, mediaType: reference.mediaType, addedAt: Date())) }
        }
    }

    // MARK: - Download state (used by the More menu)

    /// Identifier for this WHOLE title's download (movies use this directly;
    /// TV shows use it only to check "is there a whole-show download active",
    /// separate from individual per-episode downloads which have their own IDs).
    private var downloadIdentifier: String {
        "\(reference.mediaType.rawValue)-\(reference.mediaId)"
    }

    /// Non-nil while this title is actively downloading (queued/downloading/paused/failed).
    private var downloadStatus: DownloadStatus? {
        downloadManager.activeDownloads.first(where: { $0.id == downloadIdentifier })?.status
    }

    /// True once this exact title has a completed download on disk.
    private var isDownloaded: Bool {
        downloadManager.completedDownloads.contains { $0.id == downloadIdentifier }
    }

    // MARK: - More menu (Download / Share / Remove Download)

    @ViewBuilder
    private var moreMenu: some View {
        if #available(iOS 26.0, *) {
            Menu {
                menuContent
            } label: {
                menuLabel
            }
            .buttonStyle(.glass)
            .onChange(of: isDownloaded) { _, newValue in
                onDownloadCompleted(newValue)
            }
        } else {
            Menu {
                menuContent
            } label: {
                menuLabel
            }
            .buttonStyle(.bordered)
            .onChange(of: isDownloaded) { _, newValue in
                onDownloadCompleted(newValue)
            }
        }
    }

    /// Briefly shows the green checkmark for 2.5s whenever a download completes.
    private func onDownloadCompleted(_ isNowDownloaded: Bool) {
        guard isNowDownloaded else { return }
        showCompletedBriefly = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showCompletedBriefly = false
        }
    }

    /// The actual rows inside the "..." menu.
    /// - Download row: only shown if nothing is downloading/downloaded yet.
    ///   For TV, this is a nested "Download…" submenu (currently just
    ///   "Download Entire Season" — per-episode downloads live in each
    ///   episode's own context menu instead, see episodesSection below).
    /// - Share: always available.
    /// - Remove Download: only shown once downloaded, styled destructive,
    ///   always last per spec.
    @ViewBuilder
    private var menuContent: some View {
        if case .failed = downloadStatus {
            // Nothing left to cancel — this is just acknowledging a failure.
            Button {
                downloadManager.cancel(id: downloadIdentifier)
            } label: {
                Label("OK", systemImage: "exclamationmark.circle")
            }
        } else if downloadStatus != nil {
            Button(role: .destructive) {
                downloadManager.cancel(id: downloadIdentifier)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            }
        } else if !isDownloaded && !isUnreleased {
            if reference.mediaType == .tv {
                seasonDownloadMenu
            } else {
                Button {
                    Task {
                        await startDownload()
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }

        if let tmdbURL {
            ShareLink(item: tmdbURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        if isDownloaded {
            Button(role: .destructive) {
                Task { await downloadManager.delete(id: downloadIdentifier) }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }

    /// What the "..." button itself displays — changes based on state:
    /// downloading → progress ring, just completed → green check (briefly),
    /// otherwise → plain "...".
    @ViewBuilder
    private var menuLabel: some View {
        Group {
            if let downloadStatus {
                downloadProgressIcon(for: downloadStatus)
            } else if showCompletedBriefly {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "ellipsis")
            }
        }
        .frame(width: 44, height: 44)
    }

    /// A small ring showing download progress, with the percentage as text
    /// in the center. Queued shows a spinner; failed shows a red exclamation.
    @ViewBuilder
    private func downloadProgressIcon(for status: DownloadStatus) -> some View {
        switch status {
        case .downloading(let progress), .paused(let progress):
            ZStack {
                Circle().stroke(.secondary.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))")
                    .font(.system(size: 7, weight: .bold))
            }
            .frame(width: 18, height: 18)
        case .queued:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
        }
    }

    // MARK: - Download actions

    /// Downloads a whole movie (movies only — TV never calls this). Resolves
    /// the source, then hands off to the quality picker sheet instead of
    /// immediately grabbing the highest-bitrate rendition — a 4K movie can
    /// be 15-20GB, and the user should get to choose that trade-off.
    private func startDownload() async {
        do {
            let source = try await resolvePlaybackSource(media: MediaRequest(type: .movie, tmdbId: String(reference.mediaId)))
            let posterPath = reference.mediaType == .movie ? state.movieDetail?.posterPath : state.tvDetail?.posterPath

            pendingQualityDownload = PendingQualityDownload(source: source, runtimeMinutes: state.movieDetail?.runtime) { level, estimatedBytes in
                Task {
                    await downloadManager.start(
                        mediaId: reference.mediaId,
                        mediaType: reference.mediaType,
                        title: title,
                        posterPath: posterPath,
                        streamURL: source.url,
                        headers: source.headers,
                        qualityHeight: level?.maxHeight,
                        estimatedTotalBytes: estimatedBytes
                    )
                }
            }
        } catch {
            print("Download failed:", error)
        }
    }

    /// Downloads a single TV episode — used by each episode's own context menu.
    private func startEpisodeDownload(episode: SeasonDetail.Episode) async {
        do {
            let source = try await resolvePlaybackSource(media: MediaRequest(
                type: .show,
                tmdbId: String(reference.mediaId),
                season: state.selectedSeason,
                episode: episode.episodeNumber
            ))

            pendingQualityDownload = PendingQualityDownload(source: source, runtimeMinutes: nil) { level, estimatedBytes in
                Task {
                    await downloadManager.startEpisode(
                        tvId: reference.mediaId,
                        seasonNumber: state.selectedSeason,
                        episode: episode,
                        showTitle: title,
                        posterPath: state.tvDetail?.posterPath,
                        streamURL: source.url,
                        headers: source.headers,
                        qualityHeight: level?.maxHeight,
                        estimatedTotalBytes: estimatedBytes
                    )
                }
            }
        } catch {
            print("Eror startEpisodeDownload: \(error)")
        }
    }

    // MARK: - Per-episode download state

    /// Download identifier for a specific episode (matches DownloadManager.startEpisode).
    private func episodeDownloadId(_ episode: SeasonDetail.Episode) -> String {
        "tv-\(reference.mediaId)-s\(state.selectedSeason)e\(episode.episodeNumber)"
    }

    private func isEpisodeDownloaded(_ episode: SeasonDetail.Episode) -> Bool {
        downloadManager.completedDownloads.contains { $0.id == episodeDownloadId(episode) }
    }

    private func isEpisodeDownloading(_ episode: SeasonDetail.Episode) -> Bool {
        downloadManager.activeDownloads.contains { $0.id == episodeDownloadId(episode) }
    }

    private func episodeDownloadStatus(_ episode: SeasonDetail.Episode) -> DownloadStatus? {
        downloadManager.activeDownloads.first(where: { $0.id == episodeDownloadId(episode) })?.status
    }

    /// All real seasons (excludes "Specials", season 0).
    private var downloadableSeasons: [TvShowDetail.SeasonSummary] {
        (state.tvDetail?.seasons ?? []).filter { $0.seasonNumber > 0 }
    }

    private func downloadedEpisodeCount(inSeason season: Int) -> Int {
        downloadManager.completedDownloads.filter {
            $0.mediaType == .tv && $0.mediaId == reference.mediaId && $0.seasonNumber == season
        }.count
    }

    /// A season counts as fully downloaded once we hold at least as many
    /// episodes as TMDB reports for it.
    private func isSeasonFullyDownloaded(_ season: TvShowDetail.SeasonSummary) -> Bool {
        season.episodeCount > 0 && downloadedEpisodeCount(inSeason: season.seasonNumber) >= season.episodeCount
    }

    /// "Download…" submenu with one row per season: a tappable "Download Season N"
    /// or a grayed-out "Season N Downloaded" once every episode is on disk.
    @ViewBuilder
    private var seasonDownloadMenu: some View {
        Menu {
            ForEach(downloadableSeasons, id: \.seasonNumber) { season in
                if isSeasonFullyDownloaded(season) {
                    Button {} label: {
                        Label("Season \(season.seasonNumber) Downloaded", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(true)
                } else {
                    Button {
                        startSeasonDownload(season)
                    } label: {
                        Label("Download Season \(season.seasonNumber)", systemImage: "arrow.down.circle")
                    }
                }
            }
        } label: {
            Label("Download…", systemImage: "arrow.down.circle")
        }
    }

    /// Queues every episode of the given season in order, skipping any that are
    /// already downloaded, currently downloading, or not yet aired. Quality is
    /// picked once (against the first episode's playlist) and applied to the
    /// whole season, rather than prompting per-episode.
    private func startSeasonDownload(_ season: TvShowDetail.SeasonSummary) {
        Task {
            let episodes = await state.fetchEpisodes(forSeason: season.seasonNumber)
                .filter { !$0.isUnaired }
                .sorted { $0.episodeNumber < $1.episodeNumber }

            let toDownload = episodes.filter { episode in
                let id = "tv-\(reference.mediaId)-s\(season.seasonNumber)e\(episode.episodeNumber)"
                return !downloadManager.completedDownloads.contains(where: { $0.id == id })
                    && !downloadManager.activeDownloads.contains(where: { $0.id == id })
            }
            guard let first = toDownload.first else { return }

            do {
                let firstSource = try await resolvePlaybackSource(media: MediaRequest(
                    type: .show, tmdbId: String(reference.mediaId), season: season.seasonNumber, episode: first.episodeNumber
                ))

                pendingQualityDownload = PendingQualityDownload(source: firstSource, runtimeMinutes: nil) { level, _ in
                    Task {
                        for episode in toDownload {
                            do {
                                let source = episode.id == first.id
                                    ? firstSource
                                    : try await resolvePlaybackSource(media: MediaRequest(
                                        type: .show, tmdbId: String(reference.mediaId), season: season.seasonNumber, episode: episode.episodeNumber
                                    ))
                                await downloadManager.startEpisode(
                                    tvId: reference.mediaId,
                                    seasonNumber: season.seasonNumber,
                                    episode: episode,
                                    showTitle: title,
                                    posterPath: state.tvDetail?.posterPath,
                                    streamURL: source.url,
                                    headers: source.headers,
                                    qualityHeight: level?.maxHeight
                                )
                            } catch {
                                print("Season download failed for S\(season.seasonNumber)E\(episode.episodeNumber):", error)
                            }
                        }
                    }
                }
            } catch {
                print("Season download failed to resolve S\(season.seasonNumber)E\(first.episodeNumber):", error)
            }
        }
    }

    // MARK: - Overview + genre chips

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(overview).font(.body)

            if !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            Text(genre)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Info panel (runtime, release date, box office, country, links)

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if reference.mediaType == .movie, let runtime = state.movieDetail?.runtimeFormatted {
                infoRow("Runtime", "\(runtime) • Ends at \(endsAtTime)")
            }

            infoRow("Release Date", releaseDateFormatted)

            if reference.mediaType == .movie {
                if let revenue = state.movieDetail?.revenueFormatted {
                    infoRow("Box Office", revenue)
                }
                if let countries = state.movieDetail?.countryNames, !countries.isEmpty {
                    infoRow("Country") {
                        ExpandableCountriesText(countries: countries)
                    }
                }
            }

            HStack(spacing: 16) {
                if let tmdbURL { Link("TMDB", destination: tmdbURL) }
                if let imdbURL = state.externalIds?.imdbURL { Link("IMDb", destination: imdbURL) }
            }
            .font(.caption.bold())
            .padding(.top, 4)
        }
    }

    /// A plain "Label: value" row.
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    /// Same as above, but for rows needing a custom view instead of plain text
    /// (currently just the expandable country list).
    private func infoRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .font(.subheadline)
    }

    /// "Germany, Italy, and 3 more…" — tap to expand to the full list, tap again to collapse.
    private struct ExpandableCountriesText: View {
        let countries: [String]
        @State private var isExpanded = false

        var body: some View {
            if countries.count <= 2 {
                Text(countries.joined(separator: ", "))
                    .font(.subheadline)
            } else if isExpanded {
                Text(countries.joined(separator: ", "))
                    .font(.subheadline)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                    }
            } else {
                let shown = countries.prefix(2).joined(separator: ", ")
                let remaining = countries.count - 2
                (
                    Text(shown)
                    + Text(", and ")
                    + Text("\(remaining) more…").foregroundStyle(.blue)
                )
                .font(.subheadline)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
                }
            }
        }
    }

    // MARK: - Cast (movies only)

    private var castSection: some View {
        Group {
            if let credits = state.credits, !credits.cast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cast").font(.title3.bold()).padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            if let director = credits.director {
                                CastChip(name: director.name, role: "Director", imageURL: director.profileURL)
                            }
                            ForEach(credits.cast.prefix(15)) { member in
                                CastChip(name: member.name, role: member.character, imageURL: member.profileURL)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - Episodes (TV only)

    private var episodesSection: some View {
        Group {
            if let seasons = state.tvDetail?.seasons.filter({ $0.seasonNumber > 0 }), !seasons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Episodes").font(.title3.bold())
                        Spacer()
                        // Switching seasons re-fetches that season's episode list.
                        Picker("Season", selection: Binding(
                            get: { state.selectedSeason },
                            set: { newValue in Task { await state.loadSeason(newValue) } }
                        )) {
                            ForEach(seasons) { season in
                                Text(season.name).tag(season.seasonNumber)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(state.seasonEpisodes) { episode in
                                // Tap = play this episode. Long-press = Watch/Download/Share menu.
                                EpisodeCard(
                                    episode: episode,
                                    downloadStatus: episodeDownloadStatus(episode),
                                    isDownloaded: isEpisodeDownloaded(episode),
                                    isLoading: loadingEpisodeId == episode.id
                                )
                                    .onTapGesture {
                                        Task {
                                            await startPlayback(episode: episode)
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            Task {
                                                await startPlayback(episode: episode)
                                            }
                                        } label: {
                                            Label("Watch", systemImage: "play.fill")
                                        }

                                        if isEpisodeDownloaded(episode) {
                                            Button(role: .destructive) {
                                                Task {
                                                    await downloadManager.delete(id: episodeDownloadId(episode))
                                                }
                                            } label: {
                                                Label("Remove Download", systemImage: "trash")
                                            }
                                        } else if case .failed = episodeDownloadStatus(episode) {
                                            Button {
                                                downloadManager.cancel(id: episodeDownloadId(episode))
                                            } label: {
                                                Label("OK", systemImage: "exclamationmark.circle")
                                            }
                                        } else if isEpisodeDownloading(episode) {
                                            Button(role: .destructive) {
                                                downloadManager.cancel(id: episodeDownloadId(episode))
                                            } label: {
                                                Label("Cancel Download", systemImage: "xmark.circle")
                                            }
                                        } else if !episode.isUnaired {
                                            Button {
                                                Task {
                                                    await startEpisodeDownload(episode: episode)
                                                }
                                            } label: {
                                                Label("Download", systemImage: "arrow.down.circle")
                                            }
                                        }

                                        if let tmdbURL {
                                            ShareLink(item: tmdbURL) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - Similar titles

    private var similarSection: some View {
        MediaRow(
            title: reference.mediaType == .movie ? "Similar Movies" : "Similar Shows",
            items: state.similarItems,
            onSelect: { item in
                // Reuses this same sheet instead of stacking a new one —
                // handled by HomeView's .id(reference.id) + onNavigate wiring.
                onNavigate(MediaItemReference(mediaId: item.id, mediaType: item.mediaType))
            }
        )
    }

    // MARK: - Derived display values
    // These all read from `state` (the fetched detail) and branch on
    // reference.mediaType since Movie and TVShow have differently-named
    // fields for the same concepts (e.g. title/name, releaseDate/firstAirDate).

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var rawReleaseDateString: String? {
        reference.mediaType == .movie ? state.movieDetail?.releaseDate : state.tvDetail?.firstAirDate
    }

    private var parsedReleaseDate: Date? {
        guard let rawReleaseDateString else { return nil }
        return Self.isoDateFormatter.date(from: rawReleaseDateString)
    }

    /// True if the release date is in the future.
    private var isUnreleased: Bool {
        guard let parsedReleaseDate else { return false }
        return parsedReleaseDate > Date()
    }

    /// True once this title's core detail (and therefore `isUnreleased`) is
    /// known. The Play button stays disabled until then — `state.load()` runs
    /// concurrently with the poster/backdrop images, and without this gate a
    /// tap landing in that window would start playback before the button had
    /// a chance to flip to "Unreleased" (isUnreleased reads nil release date
    /// as false, i.e. "assume released", while detail is still in flight).
    private var isDetailLoaded: Bool {
        reference.mediaType == .movie ? state.movieDetail != nil : state.tvDetail != nil
    }

    private var hasRatings: Bool {
        voteCount > 0
    }

    private var backdropURL: URL? {
        reference.mediaType == .movie ? state.movieDetail?.backdropURL : state.tvDetail?.backdropURL
    }

    private var title: String {
        reference.mediaType == .movie ? (state.movieDetail?.title ?? "") : (state.tvDetail?.name ?? "")
    }

    private var overview: String {
        reference.mediaType == .movie ? (state.movieDetail?.overview ?? "") : (state.tvDetail?.overview ?? "")
    }

    private var genres: [String] {
        reference.mediaType == .movie
            ? (state.movieDetail?.genres.map(\.name) ?? [])
            : (state.tvDetail?.genres.map(\.name) ?? [])
    }

    private var voteAverage: Double {
        reference.mediaType == .movie ? (state.movieDetail?.voteAverage ?? 0) : (state.tvDetail?.voteAverage ?? 0)
    }

    private var voteCount: Int {
        reference.mediaType == .movie ? (state.movieDetail?.voteCount ?? 0) : (state.tvDetail?.voteCount ?? 0)
    }

    private var releaseYear: Int? {
        if reference.mediaType == .movie {
            guard let date = state.movieDetail?.releaseDate, date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }
        return state.tvDetail?.releaseYear
    }

    private var tmdbURL: URL? {
        let path = reference.mediaType == .movie ? "movie" : "tv"
        return URL(string: "https://www.themoviedb.org/\(path)/\(reference.id)")
    }

    /// "Play" / "Resume" (if this title already has watch progress) / "Unreleased".
    private var playButtonLabel: String {
        if isUnreleased { return "Unreleased" }
        return contentStore.recentlyWatched.contains { $0.id == reference.mediaId && $0.mediaType == reference.mediaType }
            ? "Resume" : "Play"
    }

    /// "1h 57m • Ends at 3:23 PM" — computed from runtime + current time.
    private var endsAtTime: String {
        guard let runtime = state.movieDetail?.runtime else { return "" }
        let end = Date().addingTimeInterval(TimeInterval(runtime * 60))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: end)
    }

    private var releaseDateFormatted: String {
        guard let parsedReleaseDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: parsedReleaseDate)
    }
}

// MARK: - Supporting types

/// What .fullScreenCover(item:) actually presents — bundles the source URL
/// and episode-navigation state together so PlayerView gets everything it
/// needs in one atomic value (avoids the multi-@State-write timing bug we
/// hit earlier where two separate @State vars could be read out of sync).
private struct PlaybackRequest: Identifiable {
    let id = UUID()
    let source: PlaybackSource
    let episodeState: EpisodePlaybackState
}

/// Phase 0 mpv-migration spike: bundles the real resolved URL/headers for
/// MPVSpikeView, presented instead of the normal PlayerView.
private struct MPVPlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let headers: [String: String]?
}

/// A resolved source awaiting a quality choice before the actual download
/// starts. `runtimeMinutes` (movies only) lets the picker estimate file size
/// per quality; `onSelect` receives nil level for "couldn't detect qualities,
/// just download the default rendition," and the estimated byte size (when
/// known) so the download's progress display starts from the same number the
/// user just saw here instead of 0.
private struct PendingQualityDownload: Identifiable {
    let id = UUID()
    let source: PlaybackSource
    let runtimeMinutes: Int?
    let onSelect: (PlayerQuality.Level?, Int64?) -> Void
}

/// Drives `SourcePickerSheet` when `AppSettings.manualSourceSelection` is on —
/// carries the candidates to offer and the continuation callback that resumes
/// `resolvePlaybackSource`'s awaiting call once the user responds.
private struct ManualSourcePickRequest: Identifiable {
    let id = UUID()
    let candidates: [SourceResolver.Candidate]
    let onSelect: (SourceResolver.Candidate?) -> Void
}

/// Lets the user choose which registered source to try, instead of the app
/// walking the configured order automatically. Always resolves `onSelect`
/// exactly once — with the tapped candidate, or nil on cancel/dismiss.
private struct SourcePickerSheet: View {
    let candidates: [SourceResolver.Candidate]
    let accentColor: Color
    let onSelect: (SourceResolver.Candidate?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didRespond = false

    var body: some View {
        NavigationStack {
            List(candidates, id: \.info.id) { candidate in
                Button {
                    respond(candidate)
                    dismiss()
                } label: {
                    HStack {
                        Text(candidate.info.displayName)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Choose a Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        respond(nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.black)
        .onDisappear { respond(nil) }
    }

    /// Guards against firing twice — an explicit tap/Cancel triggers `dismiss()`,
    /// which then also fires `onDisappear`.
    private func respond(_ candidate: SourceResolver.Candidate?) {
        guard !didRespond else { return }
        didRespond = true
        onSelect(candidate)
    }
}

/// Shown in place of the generic playback-error alert once every source (or
/// the user's single manually-picked one) has failed to find this title.
private struct NoSourceAvailableView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.7))
                Text("No source have this media")
                    .font(.headline)
                    .foregroundStyle(.white)
                Button("I'll watch something else", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Lets the user pick a download resolution from what the source's master
/// playlist actually offers, with an approximate file size per option when
/// the title's runtime is known. Does its own async variant lookup on
/// appearance rather than blocking the caller before the sheet shows.
/// Deliberately styled with explicit black/white/accent rather than
/// .primary/.secondary — this sheet is presented over the app's own dark
/// theme, and system-adaptive colors here were rendering low-contrast.
private struct DownloadQualityPickerSheet: View {
    let source: PlaybackSource
    let runtimeMinutes: Int?
    let accentColor: Color
    let onSelect: (PlayerQuality.Level?, Int64?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var qualities: [DownloadQualityOption] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Checking available qualities…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if qualities.isEmpty {
                    unavailableView
                } else {
                    List(qualities) { option in
                        Button {
                            onSelect(option.level, estimatedBytes(for: option))
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.level.rawValue)
                                    .foregroundStyle(.white)
                                Spacer()
                                if let size = estimatedSize(for: option) {
                                    Text("~\(size)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(accentColor)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.08))
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.black)
            .navigationTitle("Download Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.black)
        .task {
            qualities = await DownloadQualityResolver.availableQualities(for: source.url, headers: source.headers)
            isLoading = false
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.7))
            Text("Couldn't detect the available qualities for this source.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 32)
            Button("Download Anyway") {
                onSelect(nil, nil)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func estimatedBytes(for option: DownloadQualityOption) -> Int64? {
        guard let runtimeMinutes, option.approxBitrate > 0 else { return nil }
        return Int64(option.approxBitrate / 8 * Double(runtimeMinutes * 60))
    }

    private func estimatedSize(for option: DownloadQualityOption) -> String? {
        guard let bytes = estimatedBytes(for: option) else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// A cast member's circular photo + name + character/role, used in castSection.
private struct CastChip: View {
    let name: String
    let role: String
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 6) {
            FadeInImage(url: imageURL)
                .frame(width: 72, height: 72)
                .clipShape(Circle())
            Text(name).font(.caption.bold()).lineLimit(1)
            Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 80)
    }
}

/// An episode's still image (with "E3" badge) + title + short description,
/// used in episodesSection.
private struct EpisodeCard: View {
    let episode: SeasonDetail.Episode
    var downloadStatus: DownloadStatus? = nil
    var isDownloaded: Bool = false
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FadeInImage(url: episode.stillURL)
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    Text("E\(episode.episodeNumber)")
                        .font(.caption.bold())
                        .padding(6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    downloadIndicator
                        .padding(6)
                }
                .overlay {
                    if isLoading {
                        ZStack {
                            Color.black.opacity(0.45)
                            ProgressView().tint(.white).controlSize(.large)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

            Text(episode.name)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)

            if !episode.overview.isEmpty {
                Text(episode.overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(width: 240, alignment: .leading)
            }
        }
    }

    /// Top-right badge: green check once downloaded, otherwise a progress ring
    /// (or spinner while queued) while a download is in flight.
    @ViewBuilder
    private var downloadIndicator: some View {
        if isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white, .green)
                .background(.black.opacity(0.4), in: Circle())
        } else if let downloadStatus {
            switch downloadStatus {
            case .downloading(let progress), .paused(let progress):
                ZStack {
                    Circle().fill(.black.opacity(0.5))
                    Circle().stroke(.white.opacity(0.3), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
            case .queued:
                ZStack {
                    Circle().fill(.black.opacity(0.5))
                    ProgressView().controlSize(.small).tint(.white)
                }
                .frame(width: 24, height: 24)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .red)
            }
        }
    }
}
