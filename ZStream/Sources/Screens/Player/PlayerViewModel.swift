//
//  PlayerViewModel.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import AVFoundation
import CoreMedia
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    let player: AVPlayer
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = true
    @Published var didFinishPlaying = false

    private var lastSaveTime: Date = .distantPast
    private var statusCancellable: AnyCancellable?
    private let reference: MediaItemReference
    private let repository = RecentlyWatchedRepository()
    private var endObserver: NSObjectProtocol?

    private var isSeekInProgress = false
    private var pendingSeekTarget: Double?
    private var activeSeekTarget: Double?
    private var loadTimeoutTask: Task<Void, Never>?
    private var timeObserverToken: Any?
    // A quality switch replaces the item (async readyToPlay) and seeks it
    // (async completion) independently. For small/fast renditions both settle
    // almost instantly and either one calling applyPlaybackRate() is harmless.
    // Bigger renditions (e.g. a 4K/HEVC segment) take longer to become ready,
    // so the two can land far apart — whichever fires last was leaving rate
    // at 0 with nothing left to resume it. Track both and only resume once,
    // once both have actually happened for the current item.
    private var qualitySwitchAwaitingReady = false
    private var qualitySwitchAwaitingSeek = false
    // Anchor for extrapolating the play position when AVPlayer's own clock is
    // frozen — some proxied HLS streams render video while reporting a
    // non-advancing `currentTime()`. We advance from wall-time and re-sync
    // whenever the player's clock actually moves.
    private var progressAnchor: Double = 0
    private var progressWallClock: Date = .distantPast

    // MARK: Stall recovery
    // Rapid seeking and 3x/5x playback can drain the buffer faster than the proxy
    // refills it; AVPlayer then drops to `.paused` and never resumes on its own,
    // leaving playback frozen. This watchdog notices and kicks it back to life.
    private var stallObserver: NSObjectProtocol?
    private var stallStartedAt: Date?
    private var lastRecoveryAt: Date = .distantPast
    private var recoveryAttempts = 0
    private var isRecovering = false

    // MARK: Playback speed
    @Published var playbackSpeed: Float = 1.0

    // MARK: Subtitles (rendered by the app's own overlay)
    @Published var subtitleTracks: [PlaybackSubtitle] = []
    @Published var selectedSubtitleID: UUID?      // nil == off
    @Published var currentSubtitleText: String?
    private var subtitleCues: [SubtitleCue] = []
    private var subtitleLoadTask: Task<Void, Never>?

    // MARK: Embedded subtitles (in-stream legible tracks, via AVMediaSelection)
    @Published var embeddedSubtitles: [PlayerEmbeddedSubtitle] = []
    @Published var selectedEmbeddedSubtitleID: String?   // nil == off
    private var legibleGroup: AVMediaSelectionGroup?

    // MARK: Audio tracks (AVMediaSelection)
    @Published var audioTracks: [PlayerAudioOption] = []
    @Published var selectedAudioID: String?
    private var audioGroup: AVMediaSelectionGroup?

    // MARK: Diagnostics
    /// Which source (SourceInfo.id) the current stream came from, when known.
    private(set) var sourceId: String?
    /// Ticks since the last periodic status log line.
    private var ticksSinceStatusLog = 0

    // MARK: Quality
    @Published var qualities: [PlayerQuality] = []
    @Published var selectedQuality: PlayerQuality.Level = .auto
    /// The actual variant backing each selectable level (height + peak bitrate),
    /// used to force AVPlayer onto that rendition when the user picks a quality.
    private var variantByLevel: [PlayerQuality.Level: (height: Int, peakBitRate: Double)] = [:]

    //DEBUG
    private var cancellables = Set<AnyCancellable>()

    init(source: PlaybackSource, reference: MediaItemReference) {
        self.reference = reference

        Self.configureAudioSession()

        let asset = Self.makeAsset(for: source)
        let item = AVPlayerItem(asset: asset)

        self.player = AVPlayer(playerItem: item)
        // AVPlayer's default stall-minimizing heuristic fights a directly-set
        // custom `.rate` — the two "wait for more buffer" vs. "honor the rate
        // I was just told" behaviors argue with each other, and at 3x/5x this
        // showed up as playback stuttering/rubber-banding between two frames
        // instead of smoothly fast-forwarding (Apple's own docs point at this
        // exact interaction as the reason `playImmediately(atRate:)` exists).
        // Disabling it and always using `playImmediately(atRate:)` to change
        // speed (see setPlaybackSpeed) avoids the fight entirely.
        self.player.automaticallyWaitsToMinimizeStalling = false

        self.subtitleTracks = source.subtitles
        self.sourceId = source.sourceId

        observeStatus(of: item)
        observeItemLifecycle(of: item)
        startClock()
        startLoadTimeout()
        loadTracks(from: asset)
    }

    /// A wall-clock updater independent of playback progress, driven by TWO
    /// architecturally-different heartbeats feeding the same `tick()`:
    ///  - `PlayerView` drives `tick()` from a `TimelineView(.periodic(...))`,
    ///    which rides SwiftUI's own render-loop scheduling rather than a timer
    ///    or dispatch source we register ourselves — both a `RunLoop`-attached
    ///    `Timer` and a `DispatchSourceTimer` on the main queue were observed
    ///    to silently never fire at all in some environments (confirmed via
    ///    logging: registered successfully, zero callbacks, indefinitely),
    ///    while SwiftUI's own re-rendering plainly kept working throughout —
    ///    so this rides that same, confirmed-alive mechanism instead of
    ///    hoping a self-registered timer gets serviced.
    ///  - AVPlayer's periodic time observer (fires once media is genuinely
    ///    advancing; the TimelineView tick above is what covers a stream that
    ///    never starts smoothly, keeping the clock from freezing at 0:00).
    /// `lastTickAt` coalesces them so overlapping heartbeats don't double-run
    /// the per-tick work.
    private var lastTickAt: Date = .distantPast

    private func startClock() {
        reanchorProgress(to: 0)

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.tick()
        }
    }

    /// The per-tick work: refresh duration, advance the clock, drive subtitles,
    /// watch for stalls, save progress — and log a status line every ~5s. Called
    /// both by AVPlayer's periodic time observer and by `PlayerView`'s
    /// `TimelineView` heartbeat (see `startClock` for why there are two).
    func tick() {
        // Coalesce the two heartbeats: skip if the other one just ran.
        let now = Date()
        guard now.timeIntervalSince(lastTickAt) >= 0.2 else { return }
        lastTickAt = now

        let d = resolvedDuration()
        if d > 0 { duration = d }
        advanceCurrentTime()
        updateSubtitle(at: currentTime)
        monitorStall()
        if duration > 0 { saveProgressThrottled() }

        ticksSinceStatusLog += 1
        if ticksSinceStatusLog >= 20 {   // ~5s at 0.25s/tick
            ticksSinceStatusLog = 0
            let audio = audioTracks.first { $0.id == selectedAudioID }?.label ?? "default"
            let caption = subtitleTracks.first { $0.id == selectedSubtitleID }?.label
                ?? embeddedSubtitles.first { $0.id == selectedEmbeddedSubtitleID }?.label
                ?? "off"
            print("[Player] status: source=\(sourceId ?? "unknown") time=\(Int(currentTime))s/\(Int(duration))s quality=\(selectedQuality.rawValue) audio=\(audio) captions=\(caption) speed=\(playbackSpeed)x state=\(player.timeControlStatus.rawValue)")
        }
    }

    /// Resets the extrapolation anchor to a known media position "now".
    private func reanchorProgress(to seconds: Double) {
        progressAnchor = max(0, seconds)
        progressWallClock = Date()
    }

    /// Drives `currentTime`. Trusts AVPlayer's clock when it's actually moving;
    /// otherwise extrapolates from wall-time so a stream that renders video with
    /// a frozen `currentTime()` still shows a running timer. A seek's optimistic
    /// value is left untouched while the seek is in flight.
    private func advanceCurrentTime() {
        // Read the item's clock (not player.currentTime(), which can report 0 /
        // invalid on some setups even while the item's own clock is advancing).
        let playerTime = player.currentItem?.currentTime().seconds ?? .nan

        guard !isSeekInProgress else { return }

        // Whenever AVPlayer's own clock is genuinely moving, trust it and re-sync
        // (covers normal streams and corrects any extrapolation drift).
        if playerTime.isFinite, playerTime > progressAnchor + 0.25 {
            reanchorProgress(to: playerTime)
            currentTime = playerTime
            return
        }

        // Key off our own play intent, not the player's timeControlStatus: some of
        // these streams render video while sitting in `.waitingToPlayAtSpecifiedRate`
        // with a frozen currentTime(), so gating on `.playing` would freeze the UI.
        if isPlaying, !isLoading {
            var t = progressAnchor + Date().timeIntervalSince(progressWallClock) * Double(playbackSpeed)
            if duration > 0 { t = min(t, duration) }
            currentTime = t
        } else if playerTime.isFinite, playerTime >= 0 {
            // Paused or still loading — reflect the real position, hold the anchor.
            currentTime = playerTime
            reanchorProgress(to: playerTime)
        }
    }

    /// (Re)installs the end-of-playback and stall observers for an item. Both are
    /// per-item, so this runs for the initial item, each new episode, and reloads.
    private func observeItemLifecycle(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.didFinishPlaying = true
                self?.isPlaying = false
            }
        }

        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.attemptStallRecovery() }
        }
    }

    /// Surfaces an error if the item never becomes playable — some titles
    /// resolve to a valid-looking playlist whose segments then fail, leaving
    /// AVPlayer buffering forever without ever reporting `.failed`.
    private func startLoadTimeout() {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            if self.isLoading && self.errorMessage == nil {
                self.isLoading = false
                self.errorMessage = "This title couldn't be played. It may be unavailable."
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        cancellables.removeAll()
        
        statusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isLoading = false
                    self?.loadTimeoutTask?.cancel()
                    self?.loadDuration(from: item)
                    guard let self, self.player.currentItem === item else { return }
                    if self.qualitySwitchAwaitingReady {
                        self.qualitySwitchAwaitingReady = false
                        self.resumeAfterQualitySwitchIfSettled()
                    } else if self.isPlaying {
                        // canPlayFastForward/canPlaySlowForward only report real
                        // values once ready — re-apply the actually-requested
                        // speed now in case it was clamped while loading.
                        self.applyPlaybackRate()
                    }
                case .failed:
                    self?.isLoading = false
                    self?.loadTimeoutTask?.cancel()
                    self?.errorMessage = item.error?.localizedDescription ?? "This video couldn't be played."
                    // .failed only surfaces as a UI alert otherwise — print the full
                    // NSError (incl. userInfo, e.g. NSUnderlyingError) so DiagnosticsLog
                    // actually captures why, instead of just the generic alert text.
                    // The default String(describing:) can omit userInfo entries whose
                    // values aren't trivially describable, so print every key/value pair
                    // explicitly too (localizedDescription/-FailureReason/-RecoverySuggestion
                    // and any nested NSUnderlyingErrorKey).
                    if let nsError = item.error as NSError? {
                        print("[Player] item FAILED: \(nsError)")
                        print("[Player] item FAILED localizedDescription: \(nsError.localizedDescription)")
                        print("[Player] item FAILED localizedFailureReason: \(nsError.localizedFailureReason ?? "nil")")
                        print("[Player] item FAILED localizedRecoverySuggestion: \(nsError.localizedRecoverySuggestion ?? "nil")")
                        for (key, value) in nsError.userInfo {
                            print("[Player] item FAILED userInfo[\(key)] = \(value)")
                        }
                        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                            print("[Player] item FAILED underlying: domain=\(underlying.domain) code=\(underlying.code) userInfo=\(underlying.userInfo)")
                        }
                    } else {
                        print("[Player] item FAILED: \(String(describing: item.error))")
                    }
                default:
                    break
                }
            }

        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { empty in
                print("isPlaybackBufferEmpty:", empty, "at", item.currentTime().seconds)
            }
            .store(in: &cancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { likely in
                print("isPlaybackLikelyToKeepUp:", likely, "at", item.currentTime().seconds)
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { status in
                print("timeControlStatus:", status.rawValue, "at", item.currentTime().seconds)
            }
            .store(in: &cancellables)
    }
    
    /// Builds the asset for a source: routed through the HLS proxy for normal
    /// playback, or loaded directly (with any headers) when the caller opts out
    /// — e.g. the video tester playing arbitrary MP4/HLS URLs.
    private static func makeAsset(for source: PlaybackSource) -> AVURLAsset {
        if source.useProxy {
            let playbackURL = HLSPlaybackProxy.playbackURL(for: source.url, extraHeaders: source.headers)
            return AVURLAsset(url: playbackURL)
        }
        let options = source.headers.map { ["AVURLAssetHTTPHeaderFieldsKey": $0] }
        return AVURLAsset(url: source.url, options: options)
    }

    private static func configureAudioSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                print("Failed to configure audio session: \(error)")
            }
        }
    }
    
    func seek(to seconds: Double, completion: @escaping () -> Void = {}) {
        let clamped = clampToTimeline(seconds)

        // Reflect the target immediately so the scrubber/time label track the
        // request rather than waiting for playback to catch up, and re-anchor
        // extrapolation to the new position.
        currentTime = clamped
        reanchorProgress(to: clamped)

        // Coalesce rapid seeks: a new request while one is in flight replaces the
        // pending target instead of queueing. A small (non-zero) tolerance avoids
        // forcing AVPlayer to decode from an exact frame, which stalls when
        // fast-scrubbing over a flaky CDN.
        guard !isSeekInProgress else {
            pendingSeekTarget = clamped
            return
        }
        isSeekInProgress = true
        activeSeekTarget = clamped

        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeekInProgress = false
                self.activeSeekTarget = nil
                if let pending = self.pendingSeekTarget {
                    self.pendingSeekTarget = nil
                    self.seek(to: pending, completion: completion)
                } else {
                    completion()
                }
            }
        }
    }

    /// The item's playable length. HLS VOD streams frequently report
    /// `duration` as `indefinite` (NaN), so fall back to the end of the
    /// seekable range, which reflects the true length once the playlist loads.
    private func resolvedDuration() -> Double {
        guard let item = player.currentItem else { return 0 }
        let reported = item.duration.seconds
        if reported.isFinite, reported > 0 { return reported }
        if let end = item.seekableTimeRanges.last?.timeRangeValue.end.seconds, end.isFinite, end > 0 {
            return end
        }
        return 0
    }

    /// Loads the duration straight off the asset once the item is ready — a
    /// reliable path for VOD even before the seekable range has filled in.
    private func loadDuration(from item: AVPlayerItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let cm = try? await item.asset.load(.duration) {
                let secs = cm.seconds
                if secs.isFinite, secs > 0, self.duration <= 0 {
                    self.duration = secs
                }
            }
        }
    }

    private func clampToTimeline(_ seconds: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            applyPlaybackRate()
        }
        isPlaying.toggle()
        // Restart extrapolation from where we are so the timer neither jumps nor
        // freezes across a pause/resume.
        reanchorProgress(to: currentTime)
    }

    // MARK: - Stall recovery

    /// Runs every tick: if the user wants playback but AVPlayer has been stuck
    /// (paused / waiting) for a couple of seconds, kick off a recovery attempt.
    private func monitorStall() {
        guard isPlaying, !isLoading, errorMessage == nil else {
            stallStartedAt = nil
            return
        }
        let now = Date()
        switch player.timeControlStatus {
        case .playing:
            stallStartedAt = nil
            recoveryAttempts = 0
        case .paused:
            // A hard stall while the user wants playback — AVPlayer won't recover
            // this on its own, so step in quickly.
            if stallStartedAt == nil { stallStartedAt = now }
            if now.timeIntervalSince(stallStartedAt ?? now) > 1.5 { attemptStallRecovery() }
        case .waitingToPlayAtSpecifiedRate:
            // Normal buffering usually self-heals; only intervene if it drags on.
            if stallStartedAt == nil { stallStartedAt = now }
            if now.timeIntervalSince(stallStartedAt ?? now) > 8 { attemptStallRecovery() }
        @unknown default:
            break
        }
    }

    /// Nudges playback back to life after a stall. Escalates: first just resume,
    /// then re-seek to force a re-fetch of the stalled segments, and finally
    /// rebuild the player item outright if nudging keeps failing.
    private func attemptStallRecovery() {
        guard isPlaying, !isRecovering, let item = player.currentItem else { return }
        guard Date().timeIntervalSince(lastRecoveryAt) > 3 else { return }
        lastRecoveryAt = Date()
        recoveryAttempts += 1
        print("[Player] stall recovery attempt \(recoveryAttempts) at \(currentTime)s")

        if recoveryAttempts > 4 {
            reloadCurrentItem()
            return
        }

        isRecovering = true

        // Enough buffered already — a simple resume is all that's needed.
        if item.isPlaybackLikelyToKeepUp {
            applyPlaybackRate()
            isRecovering = false
            return
        }

        // Buffer is empty: re-seek to the *real* current position (not the cached
        // value, which may still be a stale 0 if playback never smoothly started)
        // so AVPlayer re-requests the segments it stalled on — served instantly
        // from the proxy cache when we already have them — then resume.
        let target = player.currentTime()
        player.seek(to: target, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.applyPlaybackRate()
                self.isRecovering = false
            }
        }
    }

    /// Last-resort recovery: rebuild the player item from the same asset at the
    /// current position. The proxy serves already-fetched segments from cache, so
    /// this re-primes AVPlayer's pipeline without re-downloading everything.
    private func reloadCurrentItem() {
        guard let asset = player.currentItem?.asset as? AVURLAsset else {
            isRecovering = false
            return
        }
        let live = player.currentTime().seconds
        let resumeAt = live.isFinite ? live : currentTime
        let desiredQuality = selectedQuality
        isRecovering = true
        isLoading = true
        print("[Player] hard reload at \(resumeAt)s")

        let item = AVPlayerItem(asset: asset)
        observeStatus(of: item)
        observeItemLifecycle(of: item)
        player.replaceCurrentItem(with: item)
        startLoadTimeout()

        player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.selectQuality(desiredQuality)
                self.applyPlaybackRate()
                self.recoveryAttempts = 0
                self.stallStartedAt = nil
                self.isRecovering = false
            }
        }
    }

    // MARK: - Playback speed

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        if #available(iOS 16.0, *) {
            player.defaultRate = speed
        }
        if isPlaying {
            // Not `player.rate = speed` — see the comment on
            // `automaticallyWaitsToMinimizeStalling` in init for why.
            applyPlaybackRate()
        }
    }

    /// Rate the current item will actually honor right now. AVFoundation
    /// gates rates above 2.0 behind `canPlayFastForward` (and below 1.0
    /// behind `canPlaySlowForward`) — both are reported `false` until the
    /// item's status is `.readyToPlay`, and forcing an unsupported rate
    /// via `playImmediately(atRate:)` drives the item straight to `.failed`
    /// with a generic AVFoundation error ("Cannot Complete Action"), which
    /// `observeStatus` then treats as fatal and closes the whole player.
    /// Clamping to what's actually supported avoids that; `.readyToPlay`
    /// re-applies the real requested speed once the gate is known for sure.
    private func supportedRate(_ rate: Float, for item: AVPlayerItem?) -> Float {
        guard let item else { return rate }
        if rate > 2.0 && !item.canPlayFastForward { return 2.0 }
        if rate < 1.0 && rate > 0 && !item.canPlaySlowForward { return 1.0 }
        return rate
    }

    /// Starts/resumes playback at `playbackSpeed`, clamped to whatever the
    /// current item actually supports (see `supportedRate`).
    private func applyPlaybackRate() {
        let item = player.currentItem
        let applied = supportedRate(playbackSpeed, for: item)
        if applied != playbackSpeed {
            print("[Player] \(playbackSpeed)x not supported by this stream yet — using \(applied)x")
        }
        player.playImmediately(atRate: applied)
    }

    // MARK: - Subtitles

    func selectSubtitle(_ id: UUID?) {
        selectedSubtitleID = id
        currentSubtitleText = nil
        subtitleCues = []
        subtitleLoadTask?.cancel()

        // The two caption systems are mutually exclusive: picking an external
        // VTT (or Off) always clears any embedded in-stream track.
        deselectEmbeddedSubtitle()

        guard let id, let track = subtitleTracks.first(where: { $0.id == id }) else { return }
        subtitleLoadTask = Task { [weak self] in
            await self?.loadSubtitle(track)
        }
    }

    /// Selects an embedded (in-stream) legible track, rendered by AVPlayer
    /// itself — clearing any app-rendered VTT selection.
    func selectEmbeddedSubtitle(_ id: String?) {
        guard let id, let track = embeddedSubtitles.first(where: { $0.id == id }) else {
            selectSubtitle(nil)   // routes through the common "everything off" path
            return
        }
        selectedSubtitleID = nil
        currentSubtitleText = nil
        subtitleCues = []
        subtitleLoadTask?.cancel()

        selectedEmbeddedSubtitleID = id
        if let legibleGroup {
            player.currentItem?.select(track.option, in: legibleGroup)
        }
        print("[Player] embedded subtitles -> \(track.label)")
    }

    private func deselectEmbeddedSubtitle() {
        selectedEmbeddedSubtitleID = nil
        if let legibleGroup {
            player.currentItem?.select(nil, in: legibleGroup)
        }
    }

    private func loadSubtitle(_ track: PlaybackSubtitle) async {
        let cues = await Self.fetchCues(from: track.url)
        await MainActor.run {
            guard !Task.isCancelled else { return }
            self.subtitleCues = cues
            if cues.isEmpty {
                print("[Subtitles] No cues parsed for \(track.label) — \(track.url)")
            } else {
                print("[Subtitles] Loaded \(cues.count) cues for \(track.label)")
            }
            self.updateSubtitle(at: self.currentTime)
        }
    }

    /// Fetches and parses a WebVTT/SRT track. Some subtitle hosts reject the
    /// vidfast referer while others require it, so we try both; likewise we fall
    /// back from UTF-8 to Latin-1 decoding.
    private static func fetchCues(from url: URL) async -> [SubtitleCue] {
        for withHeaders in [true, false] {
            var request = URLRequest(url: url)
            if withHeaders {
                request.setValue("https://vidfast.vc/", forHTTPHeaderField: "Referer")
                request.setValue("https://vidfast.vc", forHTTPHeaderField: "Origin")
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[Subtitles] HTTP \(http.statusCode) for \(url)")
                continue
            }
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            let cues = parseVTT(text)
            if !cues.isEmpty { return cues }
        }
        return []
    }

    private func updateSubtitle(at seconds: Double) {
        guard !subtitleCues.isEmpty else {
            if currentSubtitleText != nil { currentSubtitleText = nil }
            return
        }
        let cue = subtitleCues.first { seconds >= $0.start && seconds <= $0.end }
        if cue?.text != currentSubtitleText {
            currentSubtitleText = cue?.text
        }
    }

    // MARK: - Audio & quality (loaded from the asset)

    /// Loads audio tracks, embedded (in-stream) subtitle tracks, and quality
    /// variants off the asset. `includeQualities: false` is used when swapping
    /// items for a forced-quality reload — the filtered master only contains one
    /// variant, so re-reading it would wrongly shrink the quality menu.
    private func loadTracks(from asset: AVURLAsset, includeQualities: Bool = true) {
        Task { [weak self] in
            if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
                let options = group.options
                let selected = asset.preferredMediaSelection.selectedMediaOption(in: group)
                await MainActor.run {
                    self?.audioGroup = group
                    self?.audioTracks = options.enumerated().map { index, option in
                        PlayerAudioOption(id: "\(index)", label: Self.audioLabel(for: option), option: option)
                    }
                    if let selected, let index = options.firstIndex(of: selected) {
                        self?.selectedAudioID = "\(index)"
                    }
                    print("[Player] audio tracks: [\(options.map { Self.audioLabel(for: $0) }.joined(separator: ", "))]")
                }
            }

            // Embedded legible tracks (subtitles muxed into the stream). AVPlayer
            // auto-selects one of these based on system caption settings, which
            // makes subtitles appear even though the app's menu says "Off" — so
            // list them for the menu, then explicitly deselect to make Off real.
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
                let options = group.options
                await MainActor.run {
                    guard let self else { return }
                    self.legibleGroup = group
                    self.embeddedSubtitles = options.enumerated().map { index, option in
                        PlayerEmbeddedSubtitle(id: "embedded-\(index)", label: option.displayName, option: option)
                    }
                    if self.selectedEmbeddedSubtitleID == nil {
                        self.player.currentItem?.select(nil, in: group)
                    }
                    print("[Player] embedded subtitle tracks: [\(options.map(\.displayName).joined(separator: ", "))] — deselected (menu says Off)")
                }
            }

            guard includeQualities else { return }

            if let variants = try? await asset.load(.variants) {
                // Map each variant to one of our fixed levels by its actual
                // resolution, keeping the highest-bitrate rendition per level.
                var mapping: [PlayerQuality.Level: (height: Int, peakBitRate: Double)] = [:]
                for variant in variants {
                    guard let h = variant.videoAttributes?.presentationSize.height, h > 0 else { continue }
                    let height = Int(h)
                    let level = PlayerQuality.Level.level(forHeight: height)
                    let bitrate = variant.peakBitRate ?? variant.averageBitRate ?? 0
                    if let existing = mapping[level], existing.peakBitRate >= bitrate { continue }
                    mapping[level] = (height, bitrate)
                }
                // A level is available only if a matching rendition actually
                // exists; Auto is always available.
                let qualities = PlayerQuality.Level.allCases.map { level in
                    PlayerQuality(level: level, available: level == .auto || mapping[level] != nil)
                }
                await MainActor.run {
                    self?.variantByLevel = mapping
                    self?.qualities = qualities
                }
            }
        }
    }

    private static func audioLabel(for option: AVMediaSelectionOption) -> String {
        let name = option.displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.lowercased() == "unknown" { return "Default" }
        return name
    }

    func selectAudio(_ id: String) {
        guard let group = audioGroup,
              let option = audioTracks.first(where: { $0.id == id })?.option else { return }
        player.currentItem?.select(option, in: group)
        selectedAudioID = id
    }

    func selectQuality(_ level: PlayerQuality.Level) {
        guard level != selectedQuality else { return }
        selectedQuality = level
        guard let asset = player.currentItem?.asset as? AVURLAsset else { return }

        // `preferredPeakBitRate` / `preferredMaximumResolution` are down-only
        // caps — they can never force AVPlayer UP a rendition, and its bandwidth
        // estimate through the loopback proxy is unreliable enough that it often
        // refuses to leave the lowest variant. The only dependable mechanism is
        // asking the proxy to serve a master playlist containing ONLY the wanted
        // rendition (`?h=` below), then swapping the player item onto it.
        let targetHeight = level == .auto ? nil : (variantByLevel[level]?.height ?? level.maxHeight)
        let forcedURL = HLSPlaybackProxy.url(asset.url, forcingHeight: targetHeight)
        guard forcedURL != asset.url else {
            // Non-proxied stream (local file / direct URL): nothing to force.
            print("[Player] quality \(level.rawValue): stream isn't proxied, cannot force")
            return
        }

        let live = player.currentTime().seconds
        let resumeAt = live.isFinite && live > 0 ? live : currentTime
        print("[Player] quality -> \(level.rawValue)\(targetHeight.map { " (forcing \($0)p)" } ?? " (auto)"), reloading at \(Int(resumeAt))s")

        isLoading = true
        qualitySwitchAwaitingReady = true
        qualitySwitchAwaitingSeek = true
        let newAsset = AVURLAsset(url: forcedURL)
        let item = AVPlayerItem(asset: newAsset)
        observeStatus(of: item)
        observeItemLifecycle(of: item)
        player.replaceCurrentItem(with: item)
        startLoadTimeout()
        // Re-resolve audio/legible groups against the new asset (media selection
        // is per-asset), but keep the quality menu built from the full master.
        loadTracks(from: newAsset, includeQualities: false)

        player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reanchorProgress(to: resumeAt)
                self.currentTime = resumeAt
                self.qualitySwitchAwaitingSeek = false
                self.resumeAfterQualitySwitchIfSettled()
            }
        }
    }

    /// Applies the play rate once both halves of a quality switch (the new
    /// item becoming ready, and the resume-position seek completing) have
    /// landed — whichever of the two finishes last is what actually resumes
    /// playback, instead of each racing to call `applyPlaybackRate()` on its
    /// own and possibly leaving the player paused if they land far apart.
    private func resumeAfterQualitySwitchIfSettled() {
        guard !qualitySwitchAwaitingReady, !qualitySwitchAwaitingSeek else { return }
        if isPlaying {
            applyPlaybackRate()
        }
    }

    // MARK: - WebVTT parsing

    private static func parseVTT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            if lines[index].contains("-->") {
                let parts = lines[index].components(separatedBy: "-->")
                if parts.count == 2,
                   let start = parseTimestamp(parts[0]),
                   let end = parseTimestamp(parts[1]) {
                    index += 1
                    var textLines: [String] = []
                    while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        textLines.append(lines[index])
                        index += 1
                    }
                    let joined = textLines.joined(separator: "\n")
                    let stripped = joined.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    cues.append(SubtitleCue(start: start, end: end, text: stripped))
                }
            }
            index += 1
        }
        return cues
    }

    /// Parses "hh:mm:ss.mmm" or "mm:ss.mmm" (ignoring any trailing cue settings).
    private static func parseTimestamp(_ raw: String) -> Double? {
        let token = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""
        let comps = token.components(separatedBy: ":")
        let values = comps.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        guard values.count == comps.count, !values.isEmpty else { return nil }
        return values.reduce(0) { $0 * 60 + $1 }
    }

    func skip(by seconds: Double) {
        // Accumulate from where we're already heading, so tapping +10 twice in
        // quick succession advances 20s rather than collapsing to 10s (currentTime
        // hasn't moved yet while a seek is in flight).
        let base = pendingSeekTarget ?? activeSeekTarget ?? currentTime
        seek(to: base + seconds)
    }
    
    func replace(with source: PlaybackSource) {
        isLoading = true
        errorMessage = nil
        didFinishPlaying = false
        isPlaying = true
        qualitySwitchAwaitingReady = false
        qualitySwitchAwaitingSeek = false

        // New episode starts at 0 — reset the timeline and extrapolation anchor.
        currentTime = 0
        duration = 0
        reanchorProgress(to: 0)

        let asset = Self.makeAsset(for: source)
        let item = AVPlayerItem(asset: asset)

        // Reset track selections for the new episode.
        subtitleTracks = source.subtitles
        selectSubtitle(nil)
        embeddedSubtitles = []
        selectedEmbeddedSubtitleID = nil
        legibleGroup = nil
        audioTracks = []
        audioGroup = nil
        selectedAudioID = nil
        qualities = []
        selectedQuality = .auto
        variantByLevel = [:]
        sourceId = source.sourceId
        print("[Player] replacing stream — source=\(source.sourceId ?? "unknown") host=\(source.url.host ?? "?") subtitles=\(source.subtitles.count)")

        stallStartedAt = nil
        recoveryAttempts = 0
        isRecovering = false

        player.replaceCurrentItem(with: item)
        observeStatus(of: item)
        observeItemLifecycle(of: item)
        startLoadTimeout()
        loadTracks(from: asset)
        applyPlaybackRate()
    }
    
    private func saveProgressThrottled() {
        guard Date().timeIntervalSince(lastSaveTime) > 5 else { return }
        lastSaveTime = Date()
        saveProgress()
    }

    private func saveProgress() {
        // Use the resolved timeline (the raw item duration is often `indefinite`
        // for these HLS streams, and the player clock can be frozen).
        let total = duration
        guard total > 0 else { return }
        let progress = min(max(currentTime / total, 0), 1)

        Task {
            await repository.markWatched(
                RecentlyWatched(id: reference.mediaId, mediaType: reference.mediaType, progress: progress, lastWatchedAt: Date())
            )
        }
    }

    /// Called when the player screen is dismissed — stops the timer, saves
    /// one final progress snapshot, and pauses playback.
    func stop() {
        loadTimeoutTask?.cancel()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
        }

        saveProgress()
        player.pause()
    }

}

// MARK: - Supporting player-track types

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

struct PlayerAudioOption: Identifiable, Equatable {
    let id: String
    let label: String
    let option: AVMediaSelectionOption
}

/// A subtitle track embedded in the stream itself (HLS legible rendition),
/// rendered by AVPlayer via media selection — unlike PlaybackSubtitle, which
/// is an external VTT rendered by the app's own overlay.
struct PlayerEmbeddedSubtitle: Identifiable, Equatable {
    let id: String
    let label: String
    let option: AVMediaSelectionOption
}

struct PlayerQuality: Identifiable, Equatable {
    let level: Level
    let available: Bool
    var id: Level { level }

    enum Level: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case uhd = "4K"
        case fhd = "1080p"
        case hd = "720p"
        case sd = "480p"

        var id: String { rawValue }

        /// The resolution cap this level maps to; nil for Auto (no cap).
        var maxHeight: Int? {
            switch self {
            case .auto: return nil
            case .uhd: return 2160
            case .fhd: return 1080
            case .hd: return 720
            case .sd: return 480
            }
        }

        /// Buckets an actual variant height into one of the selectable levels.
        static func level(forHeight height: Int) -> Level {
            switch height {
            case 1600...: return .uhd
            case 900..<1600: return .fhd
            case 600..<900: return .hd
            default: return .sd
            }
        }
    }
}
