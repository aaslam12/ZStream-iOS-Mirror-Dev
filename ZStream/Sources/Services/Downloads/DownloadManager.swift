//
//  DownloadManager.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation
import AVFoundation
import UIKit

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var activeDownloads: [ActiveDownload] = []
    @Published private(set) var completedDownloads: [DownloadRecord] = []

    private let repository = DownloadsRepository()
    private var downloadSession: AVAssetDownloadURLSession!
    private var tasksByIdentifier: [String: AVAssetDownloadTask] = [:]

    /// Where each download's .movpkg lives on disk, as reported by
    /// willDownloadTo: (and, defensively, the legacy didFinishDownloadingTo:
    /// if that fires instead). Apple's documented guidance for this API is
    /// explicit: this location is FINAL — the asset is not a transient temp
    /// file to be relocated, unlike a plain URLSessionDownloadTask. An
    /// earlier version of this code moved the file on didFinishDownloadingTo,
    /// which both contradicted that guidance and was the actual cause of
    /// downloads that visibly finished (system "download complete" banner)
    /// but never left the Downloading list: didFinishDownloadingTo turned out
    /// to be unreliable for AVAssetDownloadConfiguration-based tasks, so the
    /// move never ran, `commitDownload`'s guard silently no-opped, and the
    /// job just sat at its last known progress forever. willDownloadTo: (the
    /// non-deprecated iOS 18+ replacement) fires reliably and early, well
    /// before completion — so this dict does NOT mean "finished," only
    /// "here's where it lives." Only didCompleteWithError(nil) means done.
    private var assetLocationsByIdentifier: [String: URL] = [:]

    override init() {
        super.init()

        let config = URLSessionConfiguration.background(
            withIdentifier: "com.z-stream.app.downloads"
        )

        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60

        downloadSession = AVAssetDownloadURLSession(
            configuration: config,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue()
        )

        // Recreating the session above with the same background identifier
        // is what lets iOS replay any delegate callbacks that were queued
        // while the app was closed (a download that finished or failed
        // mid-background). Reconnecting active/paused tasks to the UI is a
        // separate, async step — see reconnectExistingDownloads.
        Task { await reconnectExistingDownloads() }
    }

    func load() async {
        completedDownloads = await repository.loadRecords()
    }

    /// Rebuilds `activeDownloads` for tasks the OS is still tracking from a
    /// previous launch (still transferring, or suspended via pauseDownload)
    /// — without this, relaunching the app after being force-quit mid-download
    /// makes an otherwise-still-alive background transfer look like it
    /// vanished, even though `AVAssetDownloadURLSession` never actually
    /// stopped it.
    private func reconnectExistingDownloads() async {
        let pending = PendingDownloadStore.loadAll()
        guard !pending.isEmpty else { return }

        let tasks = await downloadSession.allTasks
        var stillTracked: Set<String> = []

        for task in tasks {
            guard let assetTask = task as? AVAssetDownloadTask,
                  let id = assetTask.taskDescription,
                  let meta = pending[id],
                  !activeDownloads.contains(where: { $0.id == id })
            else { continue }

            stillTracked.insert(id)
            tasksByIdentifier[id] = assetTask
            if let path = meta.assetLocationPath {
                // willDownloadTo: already fired for this task before the app
                // closed and won't fire again — restore it from disk so a
                // completion arriving post-relaunch still has somewhere to
                // commit to.
                assetLocationsByIdentifier[id] = URL(fileURLWithPath: path)
            }
            let received = task.countOfBytesReceived
            let expected = task.countOfBytesExpectedToReceive
            let progress = expected > 0 ? min(Double(received) / Double(expected), 1) : 0
            let status: DownloadStatus = task.state == .suspended
                ? .paused(progress: progress)
                : .downloading(progress: progress)
            activeDownloads.append(ActiveDownload(
                id: id,
                mediaId: meta.mediaId,
                mediaType: meta.mediaType,
                title: meta.title,
                posterPath: meta.posterPath,
                status: status,
                episodeInfo: meta.episodeInfo,
                bytesReceived: task.countOfBytesReceived,
                bytesExpected: task.countOfBytesExpectedToReceive
            ))
            print("[Downloads] reconnected \(id) — state=\(task.state.rawValue)")
        }

        // Metadata with no matching task means the OS didn't keep the
        // transfer alive — AVAssetDownloadTask's background survival across
        // a full force-quit is less reliable in practice than a plain
        // URLSessionDownloadTask's, so this isn't as rare as it should be.
        // There's no task left to resume from, but surface it as a failed,
        // acknowledgeable row instead of letting it silently vanish — that
        // silent disappearance was the actual complaint, not just "downloads
        // sometimes need restarting."
        for (id, meta) in pending where !stillTracked.contains(id) {
            PendingDownloadStore.remove(id: id)
            guard !activeDownloads.contains(where: { $0.id == id }) else { continue }
            activeDownloads.append(ActiveDownload(
                id: id, mediaId: meta.mediaId, mediaType: meta.mediaType, title: meta.title,
                posterPath: meta.posterPath,
                status: .failed("Download was interrupted while the app was closed. Please restart it."),
                episodeInfo: meta.episodeInfo
            ))
        }
    }

    // MARK: - Public entry points

    /// Downloads a whole movie (or, historically, a whole TV show as one
    /// unit — now superseded by startEpisode/startSeason for TV).
    /// `headers` should be the resolving source's own headers (Referer/Origin/
    /// User-Agent etc.) — see `startRawDownload` for why this matters.
    /// `qualityHeight` forces the proxy to thin the master playlist down to
    /// the rendition closest to that height (see `HLSPlaybackProxy.url(_:forcingHeight:)`);
    /// nil downloads whatever the source's default/highest rendition is.
    /// `estimatedTotalBytes`, when the caller has one (the quality picker
    /// computes bitrate × runtime), seeds the displayed "expected size" so it
    /// starts at a sane number instead of 0 and matches what the user was
    /// just shown, before AVFoundation's own live estimate takes over.
    func start(mediaId: Int, mediaType: MediaType, title: String, posterPath: String?, streamURL: URL, headers: [String: String]? = nil, qualityHeight: Int? = nil, estimatedTotalBytes: Int64? = nil) async {
        let id = "\(mediaType.rawValue)-\(mediaId)"
        await startRawDownload(id: id, mediaId: mediaId, mediaType: mediaType, title: title, posterPath: posterPath, streamURL: streamURL, headers: headers, qualityHeight: qualityHeight, estimatedTotalBytes: estimatedTotalBytes)
    }

    /// Downloads a single TV episode. Identifier encodes show/season/episode
    /// so it's distinct from both the whole-show ID and every other episode.
    func startEpisode(tvId: Int, seasonNumber: Int, episode: SeasonDetail.Episode, showTitle: String, posterPath: String?, streamURL: URL, headers: [String: String]? = nil, qualityHeight: Int? = nil, estimatedTotalBytes: Int64? = nil) async {
        let id = "tv-\(tvId)-s\(seasonNumber)e\(episode.episodeNumber)"
        let displayTitle = "\(showTitle) — S\(seasonNumber)E\(episode.episodeNumber)"
        await startRawDownload(
            id: id, mediaId: tvId, mediaType: .tv, title: displayTitle, posterPath: posterPath, streamURL: streamURL, headers: headers, qualityHeight: qualityHeight, estimatedTotalBytes: estimatedTotalBytes,
            episodeInfo: EpisodeInfo(showTitle: showTitle, seasonNumber: seasonNumber, episodeNumber: episode.episodeNumber, episodeTitle: episode.name, stillPath: episode.stillPath)
        )
    }

    /// Downloads every episode in the given list — used for "Download Entire Season".
    /// streamURLProvider lets the caller supply a per-episode source URL + headers.
    func startSeason(tvId: Int, seasonNumber: Int, episodes: [SeasonDetail.Episode], showTitle: String, posterPath: String?, streamURLProvider: @escaping (SeasonDetail.Episode) -> (url: URL, headers: [String: String]?)) async {
        for episode in episodes {
            let stream = streamURLProvider(episode)
            await startEpisode(
                tvId: tvId,
                seasonNumber: seasonNumber,
                episode: episode,
                showTitle: showTitle,
                posterPath: posterPath,
                streamURL: stream.url,
                headers: stream.headers
            )
        }
    }

    // MARK: - Shared download kickoff

    /// The actual AVAssetDownloadTask setup — every public start method
    /// above just computes the right identifier/title and delegates here,
    /// so there's only one place the real download logic lives.
    ///
    /// Uses `AVAssetDownloadConfiguration` (iOS 15+) rather than the older
    /// `makeAssetDownloadTask(asset:assetTitle:assetArtworkData:)`, which only
    /// ever grabs whichever ONE audio/subtitle selection happened to be
    /// current — a downloaded movie would silently lose every audio track and
    /// subtitle except the default. The configuration API downloads
    /// `auxiliaryContentConfigurations` alongside the primary content; we
    /// explicitly scope those to subtitle renditions only (see below) rather
    /// than Apple's default of "every alternate audio dub too," which was
    /// multiplying total download size/time and making completion unreliable
    /// through our single-segment-at-a-time proxy.
    private func startRawDownload(id: String, mediaId: Int, mediaType: MediaType, title: String, posterPath: String?, streamURL: URL, headers: [String: String]? = nil, qualityHeight: Int? = nil, estimatedTotalBytes: Int64? = nil, episodeInfo: EpisodeInfo? = nil) async {
        guard !activeDownloads.contains(where: { $0.id == id }) else { return }
        guard tasksByIdentifier[id] == nil else { return }

        // Route through the local HLS proxy — exactly like playback. These
        // sources disguise MPEG-TS segments as .html/.jpg with the wrong
        // Content-Type, so downloading the raw URL produces a .movpkg that
        // AVPlayer later can't open ("resource unavailable"). The proxy fixes
        // the Content-Type and injects the required headers, so the downloaded
        // package is a valid, playable HLS asset.
        //
        // `headers` MUST be the resolving source's own headers, not the
        // proxy's hardcoded vidfast.vc defaults — those only happen to work
        // for VidLink (which really is vidfast-backed). Any other source with
        // its own Referer/Origin requirement gets every segment request
        // rejected by its origin — surfaced by AVFoundation as a
        // permission-flavored NSURLError, not obviously a wrong-headers
        // problem — if this falls back to those defaults.
        var proxiedURL = HLSPlaybackProxy.playbackURL(for: streamURL, extraHeaders: headers, cacheable: false)
        if let qualityHeight {
            // Same mechanism the player uses to pin a resolution: thin the
            // master playlist down to the single closest rendition so there's
            // nothing else for the download task to grab.
            proxiedURL = HLSPlaybackProxy.url(proxiedURL, forcingHeight: qualityHeight)
        }

        let asset = AVURLAsset(url: proxiedURL)
        let downloadConfiguration = AVAssetDownloadConfiguration(asset: asset, title: title)

        // Subtitles only for auxiliary content. Apple's default here also
        // pulls in every alternate audio dub the source offers — fine for a
        // handful, but some sources have 6-8, and downloading every one of
        // them through a proxy that fetches one segment at a time is what was
        // making downloads take a very long time (and sit at ~95% well past
        // when the user expected them done). Most people want offline
        // captions, not five extra language tracks; the default audio track
        // is still part of the primary content below and always included.
        if let legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible), !legibleGroup.options.isEmpty {
            let preferred = asset.preferredMediaSelection
            let subtitleConfigs: [AVAssetDownloadContentConfiguration] = legibleGroup.options.compactMap { option in
                guard let selection = preferred.mutableCopy() as? AVMutableMediaSelection else { return nil }
                selection.select(option, in: legibleGroup)
                let config = AVAssetDownloadContentConfiguration()
                config.mediaSelections = [selection]
                return config
            }
            downloadConfiguration.auxiliaryContentConfigurations = subtitleConfigs
        } else {
            downloadConfiguration.auxiliaryContentConfigurations = []
        }

        let task = downloadSession.makeAssetDownloadTask(downloadConfiguration: downloadConfiguration)

        var job = ActiveDownload(id: id, mediaId: mediaId, mediaType: mediaType, title: title, posterPath: posterPath, status: .queued, episodeInfo: episodeInfo)
        if let estimatedTotalBytes, estimatedTotalBytes > 0 {
            job.bytesExpected = estimatedTotalBytes
        }
        activeDownloads.append(job)
        task.taskDescription = id
        tasksByIdentifier[id] = task
        PendingDownloadStore.save(id: id, meta: PendingDownloadMeta(
            mediaId: mediaId, mediaType: mediaType, title: title, posterPath: posterPath, episodeInfo: episodeInfo
        ))
        task.resume()
        print("Resumed task")
    }

    // MARK: - Cancel / pause / resume / delete

    func cancel(id: String) {
        tasksByIdentifier[id]?.cancel()
        tasksByIdentifier[id] = nil
        activeDownloads.removeAll { $0.id == id }
        PendingDownloadStore.remove(id: id)

        // AVAssetDownloadTask.cancel() leaves the partial .movpkg on disk
        // (in case you want to resume later). We don't support resuming,
        // so reclaim that space immediately.
        if let location = assetLocationsByIdentifier[id] {
            try? FileManager.default.removeItem(at: location)
            assetLocationsByIdentifier[id] = nil
        }
    }

    /// Suspends the underlying task in place — unlike `cancel`, the partial
    /// data is kept and `resumeDownload` continues from where it left off.
    func pauseDownload(id: String) {
        guard let task = tasksByIdentifier[id] else { return }
        task.suspend()
        guard let index = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
        activeDownloads[index].status = .paused(progress: activeDownloads[index].status.progressValue ?? 0)
    }

    func resumeDownload(id: String) {
        guard let task = tasksByIdentifier[id] else { return }
        task.resume()
        guard let index = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
        activeDownloads[index].status = .downloading(progress: activeDownloads[index].status.progressValue ?? 0)
    }

    func delete(id: String) async {
        await repository.remove(id: id)
        completedDownloads.removeAll { $0.id == id }
    }

    /// Sums each record's own measured size rather than scanning
    /// `DownloadStorage.directory` — completed downloads now live wherever
    /// AVFoundation put them (see `DownloadRecord.localFileURL`'s doc
    /// comment), not necessarily under that directory, so a disk scan there
    /// would undercount.
    var totalStorageUsed: Int64 {
        completedDownloads.reduce(0) { $0 + $1.fileSizeBytes }
    }

    // MARK: - Delegate callback handlers
    // (called from the AVAssetDownloadDelegate methods below, always
    // hopped onto @MainActor first since the delegate methods themselves
    // are nonisolated and can arrive on a background queue)

    /// `timeBasedProgress` is what `didLoad:totalTimeRangesLoaded:timeRangeExpectedToLoad:`
    /// reports — it tracks the PRIMARY content's timeline only, so it can (and
    /// does) hit 100% once the video+default-audio pass is fully loaded while
    /// auxiliary subtitle content is still being fetched behind it. That
    /// mismatch is exactly what showed a "100%" progress bar next to a byte
    /// count that never actually finished. Bytes cover everything actually
    /// being downloaded, so prefer that once we have a real expected size.
    fileprivate func updateProgress(id: String, timeBasedProgress: Double, bytesReceived: Int64, bytesExpected rawBytesExpected: Int64) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == id }) else { return }

        // AVFoundation's own byte estimate is a noisy, constantly-revised
        // guess that can swing by gigabytes as it discovers more of the
        // playlist — never let the displayed number visibly shrink.
        let stableExpected = max(activeDownloads[index].bytesExpected, rawBytesExpected)

        // A pause can race a progress callback already in flight — don't let
        // a stale "downloading" overwrite a status the user just paused.
        if case .paused = activeDownloads[index].status {
            activeDownloads[index].bytesReceived = bytesReceived
            activeDownloads[index].bytesExpected = stableExpected
            return
        }

        let effectiveProgress = stableExpected > 0
            ? Double(bytesReceived) / Double(stableExpected)
            : timeBasedProgress
        // Never claim 100% here — only didCompleteWithError actually knows
        // the download is done. Otherwise the row reads "done" while data is
        // still trickling in for auxiliary content.
        let displayProgress = min(max(effectiveProgress, 0), 0.99)

        activeDownloads[index].status = .downloading(progress: displayProgress)
        activeDownloads[index].bytesReceived = bytesReceived
        activeDownloads[index].bytesExpected = stableExpected
    }

    /// Called from didCompleteWithError once we've confirmed error == nil —
    /// registers the already-in-place .movpkg (at the location willDownloadTo:
    /// reported) as a completed download. Does NOT move or copy it — see
    /// assetLocationsByIdentifier's doc comment for why that used to be a bug.
    fileprivate func commitDownload(id: String) {
        guard let location = assetLocationsByIdentifier[id] else {
            // Never got a location for this id (willDownloadTo: never fired) —
            // nothing to commit, and no file to have gone looking for.
            failDownload(id: id, message: "Couldn't save the download — no destination was reported.")
            return
        }
        guard FileManager.default.fileExists(atPath: location.path) else {
            failDownload(id: id, message: "Couldn't save the download — the file went missing.")
            return
        }
        // The job may not be in `activeDownloads` yet — e.g. this callback is
        // a replay of a download that finished while the app was closed, and
        // `reconnectExistingDownloads` hasn't (or can't, since the task is
        // already gone from the session) reconstructed it. Fall back to the
        // persisted metadata rather than silently dropping a finished file.
        guard let job = activeDownloads.first(where: { $0.id == id }) ?? PendingDownloadStore.loadAll()[id].map({ meta in
            ActiveDownload(id: id, mediaId: meta.mediaId, mediaType: meta.mediaType, title: meta.title, posterPath: meta.posterPath, status: .queued, episodeInfo: meta.episodeInfo)
        }) else { return }

        tasksByIdentifier[id] = nil
        assetLocationsByIdentifier[id] = nil
        PendingDownloadStore.remove(id: id)

        let size = directorySize(at: location)

        let record = DownloadRecord(
            id: id,
            mediaId: job.mediaId,
            mediaType: job.mediaType,
            title: job.title,
            posterPath: job.posterPath,
            fileSizeBytes: Int64(size),
            downloadedAt: Date(),
            localFileName: location.lastPathComponent,
            showTitle: job.episodeInfo?.showTitle,
            seasonNumber: job.episodeInfo?.seasonNumber,
            episodeNumber: job.episodeInfo?.episodeNumber,
            episodeTitle: job.episodeInfo?.episodeTitle,
            episodeStillPath: job.episodeInfo?.stillPath,
            localFileURL: location
        )

        Task {
            await repository.add(record)
            activeDownloads.removeAll { $0.id == id }
            completedDownloads.insert(record, at: 0)
        }
    }

    fileprivate func failDownload(id: String, message: String) {
        tasksByIdentifier[id] = nil

        if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[index].status = .failed(message)
        } else if let meta = PendingDownloadStore.loadAll()[id] {
            // Same replay-while-closed situation as commitDownload: surface
            // the failure as a fresh row so the user still sees (and can
            // acknowledge) it instead of it vanishing without a trace.
            activeDownloads.append(ActiveDownload(
                id: id, mediaId: meta.mediaId, mediaType: meta.mediaType, title: meta.title,
                posterPath: meta.posterPath, status: .failed(message), episodeInfo: meta.episodeInfo
            ))
        }
        PendingDownloadStore.remove(id: id)

        // A failed download can leave partial data behind — reclaim it
        // rather than silently keeping a truncated file around.
        if let location = assetLocationsByIdentifier[id] {
            try? FileManager.default.removeItem(at: location)
            assetLocationsByIdentifier[id] = nil
        }
    }

    /// Translates the raw NSError from a failed download into something a
    /// user can actually act on. AVFoundation surfaces most segment-fetch
    /// failures (dead links, origin returning 503/404, expired signed URLs)
    /// as opaque `CoreMediaErrorDomain` codes like -16849 — meaningless
    /// without knowing HTTP status semantics, so treat that whole family
    /// (and anything else that isn't a plain connectivity problem) as
    /// "this download isn't available right now" instead.
    private static func friendlyMessage(for error: NSError) -> String {
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut:
                return "Lost connection. Check your internet and try again."
            default:
                break
            }
        }
        return "This download is not available right now."
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}

extension DownloadManager: AVAssetDownloadDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }

        var loadedDuration = 0.0
        for value in loadedTimeRanges {
            loadedDuration += value.timeRangeValue.duration.seconds
        }
        let totalDuration = timeRangeExpectedToLoad.duration.seconds
        guard totalDuration > 0 else { return }
        let timeBasedProgress = min(loadedDuration / totalDuration, 1)
        let received = assetDownloadTask.countOfBytesReceived
        let expected = assetDownloadTask.countOfBytesExpectedToReceive

        Task { @MainActor in
            self.updateProgress(id: id, timeBasedProgress: timeBasedProgress, bytesReceived: received, bytesExpected: expected)
        }
    }

    /// Deprecated by Apple in favor of willDownloadTo: below (which fires
    /// reliably, early, for AVAssetDownloadConfiguration-based tasks) — kept
    /// only as a defensive fallback in case this fires instead. Must NOT move
    /// the file: Apple's documented guidance is that this location is the
    /// asset's actual final location on disk, not a temp file to relocate.
    /// An earlier version of this code moved it, which both violated that
    /// guidance and, more concretely, was why downloads that visibly
    /// finished (system "download complete" banner) never left the
    /// Downloading list — this callback turned out not to reliably fire at
    /// all for this task type, so the move never ran and commitDownload's
    /// lookup silently found nothing.
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        Task { @MainActor in
            self.assetLocationsByIdentifier[id] = location
            PendingDownloadStore.updateAssetLocation(id: id, path: location.path)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = task.taskDescription else { return }

        if let error {
            let nsError = error as NSError

            print("""
            ===== DOWNLOAD ERROR =====
            Domain: \(nsError.domain)
            Code: \(nsError.code)
            UserInfo:
            \(nsError.userInfo)
            ==========================
            """)

            // Background download is being retried by iOS.
            if nsError.domain == NSURLErrorDomain &&
                nsError.code == NSURLErrorNetworkConnectionLost {
                return
            }

            if nsError.domain == NSURLErrorDomain &&
                nsError.code == NSURLErrorTimedOut {
                return
            }

            Task { @MainActor in
                self.failDownload(
                    id: id,
                    message: Self.friendlyMessage(for: nsError)
                )
            }

        } else {
            print("Download completed without error.")
            Task { @MainActor in
                self.commitDownload(id: id)
            }
        }
    }
    
    // NOTE: didReceive response:/completionHandler: (URLSessionDataDelegate)
    // was removed — AVAssetDownloadTask doesn't go through that delegate at
    // all, so it never fired regardless of signature.

    nonisolated func urlSession(
        _ session: URLSession,
        taskIsWaitingForConnectivity task: URLSessionTask
    ) {
        print("Waiting for connectivity")
    }

    /// Fires once every queued delegate callback for this background session
    /// has been delivered — the system's cue that it's safe to tell it we're
    /// done processing, via the completion handler `AppDelegate` stashed from
    /// `handleEventsForBackgroundURLSession`. Only relevant when iOS woke the
    /// app specifically to deliver these events (not a normal foreground launch,
    /// where there's no stashed handler and this is a no-op).
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                  let handler = appDelegate.backgroundDownloadsCompletionHandler else { return }
            appDelegate.backgroundDownloadsCompletionHandler = nil
            handler()
        }
    }

    /// Fires early — before real data flows — with the asset's actual final
    /// on-disk location (Apple: "This URL should be saved for future
    /// instantiations of AVAsset"). This is the source of truth for where a
    /// completed download will end up; commitDownload only trusts it once
    /// didCompleteWithError separately confirms the transfer succeeded.
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        print("[Downloads] \(id) will download to:", location)
        Task { @MainActor in
            self.assetLocationsByIdentifier[id] = location
            PendingDownloadStore.updateAssetLocation(id: id, path: location.path)
        }
    }
}
