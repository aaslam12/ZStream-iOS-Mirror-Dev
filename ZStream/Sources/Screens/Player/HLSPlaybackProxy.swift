//
//  HLSPlaybackProxy.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/22/26.
//

import Foundation
import Network

/// Local HTTP proxy for playing disguised HLS streams through AVPlayer.
///
/// These sources hide MPEG-TS segments behind fake extensions (`.jpg`, `.html`)
/// and mislabel them (`image/jpeg`, `text/html`), and they require referer /
/// origin headers on every request. AVPlayer's own HLS engine can't demux them
/// directly, and feeding the bytes through an `AVAssetResourceLoader` custom
/// scheme fails at the demux stage (CoreMediaErrorDomain -12881).
///
/// Instead we run a tiny HTTP server bound to 127.0.0.1. AVPlayer loads a normal
/// `http://127.0.0.1/...` HLS URL and does its native (rock-solid) demuxing; we
/// simply rewrite playlist URIs to point back at ourselves and correct the
/// `Content-Type` of every segment on the way through.
enum HLSPlaybackProxy {

    /// Returns a loopback URL AVPlayer can play. Starts the server on first use.
    ///
    /// Only remote http(s) streams are proxied; local files (offline downloads,
    /// which are self-contained `.movpkg` bundles) are returned untouched so
    /// AVPlayer reads them directly from disk.
    /// - Parameter cacheable: whether the proxy should keep fetched segments in
    ///   its in-memory cache. True for playback (helps seeking); pass **false**
    ///   for downloads, which read each segment exactly once — caching them just
    ///   wastes memory and risks the download being jettisoned on a big movie.
    static func playbackURL(for url: URL, extraHeaders: [String: String]? = nil, cacheable: Bool = true) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return url
        }
        return ProxyServer.shared.playbackURL(for: url, extraHeaders: extraHeaders, cacheable: cacheable)
    }

    /// Rewrites an already-proxied URL to force (or clear) a quality: the proxy
    /// thins the master playlist to the rendition closest to `height`, which is
    /// the only reliable way to pin AVPlayer to an exact resolution. Pass nil to
    /// restore automatic variant selection. Non-proxy URLs are returned as-is.
    static func url(_ proxied: URL, forcingHeight height: Int?) -> URL {
        guard proxied.host == "127.0.0.1",
              var components = URLComponents(url: proxied, resolvingAgainstBaseURL: false) else {
            return proxied
        }
        components.queryItems = height.map { [URLQueryItem(name: "h", value: String($0))] }
        return components.url ?? proxied
    }
}

private final class ProxyServer {

    static let shared = ProxyServer()

    private static let defaultHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://vidfast.vc/",
        "Origin": "https://vidfast.vc"
    ]

    /// Flip to false to silence proxy diagnostics.
    private static let verbose = true

    private let queue = DispatchQueue(label: "com.zstream.hlsproxy.server", attributes: .concurrent)
    private var _listener: NWListener?
    private var _port: UInt16?
    private var _headers: [String: String] = defaultHeaders
    private let session: URLSession
    private let cache = SegmentCache(capacityBytes: 220 * 1024 * 1024)

    // `queue` is concurrent and NWListener dispatches connection callbacks on
    // it in parallel, so plain stored properties touched from those callbacks
    // (port assigned when the listener comes up, headers replaced whenever a
    // new playback/quality-switch starts) are a real data race, not just a
    // theoretical one — a switch's `proxy()` call can read `headers` mid-write
    // from a concurrent call. Route every access through this lock.
    private let stateLock = NSLock()
    private var isStarting = false
    private var port: UInt16? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _port }
        set { stateLock.lock(); _port = newValue; stateLock.unlock() }
    }
    private var headers: [String: String] {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _headers }
        set { stateLock.lock(); _headers = newValue; stateLock.unlock() }
    }
    private var listener: NWListener? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _listener }
        set { stateLock.lock(); _listener = newValue; stateLock.unlock() }
    }

    // AVFoundation routinely issues several concurrent requests for the exact
    // same playlist/segment URL during a single load or quality switch (once
    // for the player item's own pipeline, again per media-selection-group
    // lookup — confirmed via duplicate FILTER/PLAYLIST log lines). Without
    // coalescing, each one independently re-fetches the origin; against a
    // CDN that signs/limits tokens per request, the losers of that race can
    // come back 500, or the item can be swapped mid-flight onto inconsistent
    // state. One in-flight fetch per origin URL, shared by every caller.
    private var inFlightFetches: [String: Task<(Data, URLResponse), Error>] = [:]

    private func fetchOrigin(_ request: URLRequest, key: String) async throws -> (Data, URLResponse) {
        stateLock.lock()
        if let existing = inFlightFetches[key] {
            stateLock.unlock()
            log("FETCH join existing \(key.prefix(50))…")
            let result = try await existing.value
            log("FETCH joined-result \(key.prefix(50))…")
            return result
        }
        let task = Task<(Data, URLResponse), Error> { [session] in
            try await session.data(for: request)
        }
        inFlightFetches[key] = task
        stateLock.unlock()
        defer {
            stateLock.lock()
            inFlightFetches[key] = nil
            stateLock.unlock()
        }
        log("FETCH new \(key.prefix(50))…")
        let result = try await task.value
        log("FETCH done \(key.prefix(50))…")
        return result
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: Public entry

    func playbackURL(for origin: URL, extraHeaders: [String: String]?, cacheable: Bool) -> URL {
        var merged = Self.defaultHeaders
        extraHeaders?.forEach { merged[$0] = $1 }
        headers = merged

        startIfNeeded()

        let port = self.port ?? 0
        return Self.localURL(for: origin, port: port, cacheable: cacheable)
    }

    // MARK: Server lifecycle

    private func startIfNeeded() {
        stateLock.lock()
        // Read the backing stores directly, not the locked `listener`/`headers`
        // computed properties -- NSLock isn't reentrant, so calling their
        // getters while already holding stateLock here deadlocks every call.
        guard _listener == nil, !isStarting else { stateLock.unlock(); return }
        // Claim the slot before doing any of the actual setup below, so a
        // second concurrent caller's guard above bails instead of racing to
        // start a second listener.
        isStarting = true
        stateLock.unlock()
        defer { stateLock.lock(); isStarting = false; stateLock.unlock() }

        let semaphore = DispatchSemaphore(value: 0)
        do {
            let listener = try NWListener(using: .tcp)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = listener.port?.rawValue
                    self?.log("listening on 127.0.0.1:\(self?.port ?? 0)")
                    semaphore.signal()
                case .failed(let error):
                    self?.log("listener failed: \(error)")
                    semaphore.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            // Block briefly (off the listener's queue) until the port is assigned.
            _ = semaphore.wait(timeout: .now() + 3)
        } catch {
            log("failed to start listener: \(error)")
        }
    }

    // MARK: Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
                self.handleRequest(headerData, on: connection)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handleRequest(_ headerData: Data, on connection: NWConnection) {
        guard let text = String(data: headerData, encoding: .utf8) else {
            respond(status: 400, contentType: "text/plain", body: Data(), on: connection)
            return
        }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(status: 400, contentType: "text/plain", body: Data(), on: connection)
            return
        }

        let path = String(parts[1])
        let range = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }
            .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }

        guard let decoded = Self.decodeOrigin(fromPath: path) else {
            respond(status: 404, contentType: "text/plain", body: Data(), on: connection)
            return
        }

        log("REQUEST \(path.prefix(40))… range=\(range ?? "-") forceHeight=\(decoded.forceHeight.map(String.init) ?? "-")")
        Task { await self.proxy(origin: decoded.origin, range: range, cacheable: decoded.cacheable, forceHeight: decoded.forceHeight, on: connection) }
    }

    private func proxy(origin: URL, range: String?, cacheable: Bool, forceHeight: Int?, on connection: NWConnection) async {
        let key = origin.absoluteString
        log("PROXY START key=\(key.prefix(60))…")

        // Serve a segment straight from cache when we've already fetched it —
        // this makes seeking cheap and survives AVPlayer abandoning/re-opening
        // connections, without depending on the origin honoring Range requests.
        // Downloads pass cacheable=false and skip the cache entirely.
        if cacheable, let cached = await cache.data(for: key) {
            serveSegment(cached, rangeHeader: range, on: connection)
            return
        }

        var request = URLRequest(url: origin)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        // Deliberately do NOT forward Range to the origin: we fetch the whole
        // resource once, cache it, and satisfy every (sub)range locally.

        do {
            var (data, response) = try await fetchOrigin(request, key: key)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200

            guard (200..<400).contains(status) else {
                let headerDump = headers.map { "\($0)=\($1)" }.sorted().joined(separator: ", ")
                let respHeaders = (response as? HTTPURLResponse)?.allHeaderFields
                    .map { "\($0)=\($1)" }.sorted().joined(separator: ", ") ?? ""
                log("origin FAILED url=\(origin.absoluteString) status=\(status) sentHeaders=[\(headerDump)] responseHeaders=[\(respHeaders)] bodyPrefix=\(String(data: data.prefix(300), encoding: .utf8) ?? "<\(data.count) non-utf8 bytes>")")
                respond(status: status, contentType: "text/plain", body: Data(), on: connection)
                return
            }

            if isPlaylist(data) {
                // When a quality is forced, thin the master playlist down to the
                // single closest rendition BEFORE rewriting URIs — AVPlayer then
                // has no other variant to fall back to, which is the only
                // reliable way to force an exact resolution (bitrate/resolution
                // "preferences" are down-only caps and ABR through a loopback
                // proxy mis-measures bandwidth anyway).
                var playlistData = data
                if let forceHeight {
                    playlistData = Self.filterMaster(playlistData, toHeight: forceHeight, logger: { self.log($0) })
                }
                let body = rewritePlaylist(playlistData, baseURL: origin, cacheable: cacheable)
                log("PLAYLIST \(Self.playlistSummary(playlistData)) (\(data.count) -> \(body.count) bytes)\(forceHeight.map { " forcedHeight=\($0)" } ?? "")")
                respond(status: 200, contentType: "application/vnd.apple.mpegurl", body: body, on: connection)
            } else {
                // Segment names carry a huge signed token; log only a short prefix.
                log("SEGMENT \(origin.lastPathComponent.prefix(12))… bytes=\(data.count)")
                // Small fMP4 responses are almost always the init segment (moov box,
                // carrying the hvcC/colr codec parameters) rather than real media —
                // dump it so a codec-rejection failure can actually be diagnosed
                // instead of just seeing the opaque CoreMedia error code.
                if data.count < 20_000, data.count >= 8,
                   let box = String(data: data.subdata(in: data.index(data.startIndex, offsetBy: 4)..<data.index(data.startIndex, offsetBy: 8)), encoding: .ascii),
                   box == "ftyp" {
                    if let patched = Self.patchOverdeclaredHEVCLevel(data, logger: { self.log($0) }) {
                        data = patched
                    }
                    log("INIT SEGMENT hex (\(data.count) bytes): \(data.map { String(format: "%02x", $0) }.joined())")
                } else if let forceHeight, forceHeight >= 2160,
                          let patched = Self.injectHDRMetadataSEI(data, logger: { self.log($0) }) {
                    data = patched
                }
                if cacheable {
                    await cache.store(data, for: key)
                }
                serveSegment(data, rangeHeader: range, on: connection)
            }
        } catch {
            log("fetch error \(origin.lastPathComponent): \(error.localizedDescription)")
            respond(status: 502, contentType: "text/plain", body: Data(), on: connection)
        }
    }

    /// Serves a fully-fetched segment, honoring an optional client byte range by
    /// slicing the cached data (206) rather than re-fetching from the origin.
    private func serveSegment(_ full: Data, rangeHeader: String?, on connection: NWConnection) {
        let contentType = segmentMimeType(for: full)
        let total = full.count

        if let (start, end) = Self.parseByteRange(rangeHeader, total: total) {
            let slice = full.subdata(in: start..<(end + 1))
            respond(
                status: 206,
                contentType: contentType,
                body: slice,
                contentRange: "bytes \(start)-\(end)/\(total)",
                on: connection
            )
        } else {
            respond(status: 200, contentType: contentType, body: full, on: connection)
        }
    }

    /// Parses a `Range: bytes=…` header into a concrete inclusive [start, end]
    /// clamped to the resource, or nil for "serve the whole thing".
    private static func parseByteRange(_ header: String?, total: Int) -> (start: Int, end: Int)? {
        guard total > 0,
              let header,
              let equals = header.firstIndex(of: "="),
              header[header.startIndex..<equals].lowercased().hasSuffix("bytes")
        else { return nil }

        let spec = header[header.index(after: equals)...]
        // Only the first range in a (rare) multi-range request is honored.
        let firstSpec = spec.split(separator: ",").first.map(String.init) ?? String(spec)
        let bounds = firstSpec.split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }

        let startStr = bounds[0].trimmingCharacters(in: .whitespaces)
        let endStr = bounds[1].trimmingCharacters(in: .whitespaces)

        let start: Int
        let end: Int
        if startStr.isEmpty {
            // Suffix range: bytes=-N (last N bytes).
            guard let suffix = Int(endStr), suffix > 0 else { return nil }
            start = max(0, total - suffix)
            end = total - 1
        } else {
            guard let s = Int(startStr) else { return nil }
            start = s
            end = endStr.isEmpty ? total - 1 : min(Int(endStr) ?? (total - 1), total - 1)
        }

        guard start <= end, start < total, start >= 0 else { return nil }
        return (start, end)
    }

    // MARK: HTTP response

    private func respond(
        status: Int,
        contentType: String,
        body: Data,
        contentRange: String? = nil,
        on connection: NWConnection
    ) {
        var header = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        if let contentRange { header += "Content-Range: \(contentRange)\r\n" }
        header += "Connection: close\r\n\r\n"

        var payload = Data(header.utf8)
        payload.append(body)

        // Send as the final message with a graceful close. Cancelling here would
        // send an abortive RST and truncate large segments still draining from
        // the OS socket buffer — which stalls playback a few seconds in. Instead
        // we wait for the client to finish reading and close its side.
        connection.send(content: payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] error in
            // A reset/broken-pipe here is normal: AVPlayer abandons a segment's
            // connection the moment it seeks away. The peer is already gone, so
            // just drop it — nothing to drain.
            if error != nil {
                connection.cancel()
            } else {
                self?.awaitClose(connection)
            }
        })
    }

    /// Tears the connection down only after the client (AVPlayer) has read the
    /// full response and closed, so no bytes are lost. A timeout guards against a
    /// client that lingers.
    private func awaitClose(_ connection: NWConnection) {
        queue.asyncAfter(deadline: .now() + 20) { connection.cancel() }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, isComplete, error in
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    // MARK: Playlist rewriting

    /// Summarizes a playlist for diagnostics: whether it's a master or media
    /// playlist, its VOD/live signaling, segment count, and total EXTINF length.
    /// A frozen on-screen clock usually traces back to a media playlist that
    /// lacks `#EXT-X-ENDLIST` (AVPlayer then treats it as live).
    private static func playlistSummary(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "non-utf8" }
        if text.contains("#EXT-X-STREAM-INF") {
            let variants = text.components(separatedBy: "\n").filter { $0.hasPrefix("#EXT-X-STREAM-INF") }.count
            return "MASTER variants=\(variants)"
        }
        let hasEndList = text.contains("#EXT-X-ENDLIST")
        let type = text.components(separatedBy: "\n")
            .first { $0.hasPrefix("#EXT-X-PLAYLIST-TYPE") }?
            .components(separatedBy: ":").last ?? "none"
        var total = 0.0
        var segs = 0
        for line in text.components(separatedBy: "\n") where line.hasPrefix("#EXTINF:") {
            total += Double(line.dropFirst(8).components(separatedBy: ",").first ?? "") ?? 0
            segs += 1
        }
        return "MEDIA type=\(type) endlist=\(hasEndList) segs=\(segs) totalDur=\(String(format: "%.0f", total))s"
    }

    private func isPlaylist(_ data: Data) -> Bool {
        var bytes = Array(data.prefix(64))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        guard let head = String(bytes: bytes, encoding: .utf8) else { return false }
        return head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
    }

    /// Rewrites every child URI (variants, segments, keys, maps) so it loops back
    /// through this proxy — carrying the original absolute URL in the path. The
    /// `cacheable` mode is propagated to every child so a download's whole tree
    /// consistently bypasses the cache.
    private func rewritePlaylist(_ data: Data, baseURL: URL, cacheable: Bool) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let port = self.port ?? 0

        let rewritten = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            if trimmed.hasPrefix("#") { return rewriteTagURI(in: line, baseURL: baseURL, port: port, cacheable: cacheable) }
            return proxyURIString(trimmed, baseURL: baseURL, port: port, cacheable: cacheable)
        }
        return Data(rewritten.joined(separator: "\n").utf8)
    }

    private func rewriteTagURI(in line: String, baseURL: URL, port: UInt16, cacheable: Bool) -> String {
        guard let range = line.range(of: #"URI="([^"]*)""#, options: .regularExpression) else {
            return line
        }
        let inner = line[range].dropFirst(5).dropLast()
        let proxied = proxyURIString(String(inner), baseURL: baseURL, port: port, cacheable: cacheable)
        return line.replacingCharacters(in: range, with: "URI=\"\(proxied)\"")
    }

    private func proxyURIString(_ uri: String, baseURL: URL, port: UInt16, cacheable: Bool) -> String {
        guard let resolved = URL(string: uri, relativeTo: baseURL)?.absoluteURL else { return uri }
        return Self.localURL(for: resolved, port: port, cacheable: cacheable).absoluteString
    }

    // MARK: URL <-> path encoding

    // Cacheable requests use the `/p/` path; non-cacheable (download) requests
    // use `/pd/`, so the handler knows whether to populate the segment cache.
    private static func localURL(for origin: URL, port: UInt16, cacheable: Bool) -> URL {
        let encoded = Data(origin.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let prefix = cacheable ? "p" : "pd"
        return URL(string: "http://127.0.0.1:\(port)/\(prefix)/\(encoded)")!
    }

    private static func decodeOrigin(fromPath path: String) -> (origin: URL, cacheable: Bool, forceHeight: Int?)? {
        // Split off the query — `h=<height>` asks the proxy to thin a master
        // playlist down to the rendition closest to that height.
        let pieces = path.split(separator: "?", maxSplits: 1)
        let purePath = String(pieces.first ?? "")
        var forceHeight: Int? = nil
        if pieces.count == 2 {
            for pair in pieces[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "h", let value = Int(kv[1]), value > 0 {
                    forceHeight = value
                }
            }
        }

        let cacheable: Bool
        let token: String
        if purePath.hasPrefix("/pd/") {
            cacheable = false
            token = String(purePath.dropFirst(4))
        } else if purePath.hasPrefix("/p/") {
            cacheable = true
            token = String(purePath.dropFirst(3))
        } else {
            return nil
        }

        var normalized = token.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        normalized += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: normalized),
              let string = String(data: data, encoding: .utf8),
              let url = URL(string: string) else {
            return nil
        }
        return (url, cacheable, forceHeight)
    }

    // MARK: HEVC level correction

    /// Some encodes stamp an inflated HEVC `level_idc` in the `hvcC` box (e.g.
    /// Level 6.0, meant for 8K) on ordinary 4K content, likely from an encoder
    /// bitrate heuristic rather than the content actually needing it. iOS's
    /// hardware decoder validates the declared level and rejects the whole item
    /// with CoreMediaErrorDomain -12927 if it exceeds what's supported — even
    /// though the real resolution/bitrate would decode fine. Clamp it down to
    /// Level 5.1 (153), the ceiling real 4K content should ever need.
    private static func patchOverdeclaredHEVCLevel(_ data: Data, logger: (String) -> Void = { _ in }) -> Data? {
        var bytes = [UInt8](data)
        guard let payload = hvcCPayloadIndex(bytes), payload + 22 < bytes.count else { return nil }
        let maxLevel: UInt8 = 153 // Level 5.1
        var didPatch = false

        let profileIdc = bytes[payload + 1] & 0x1f
        let chromaFormatIdc = bytes[payload + 16] & 0x03
        let bitDepthLuma = (bytes[payload + 17] & 0x07) + 8
        let bitDepthChroma = (bytes[payload + 18] & 0x07) + 8
        logger("HEVC hvcC profile_idc=\(profileIdc) chroma_format_idc=\(chromaFormatIdc) bit_depth_luma=\(bitDepthLuma) bit_depth_chroma=\(bitDepthChroma)")

        let headerLevel = payload + 12
        if bytes[headerLevel] > maxLevel {
            let original = bytes[headerLevel]
            bytes[headerLevel] = maxLevel
            didPatch = true
            logger("HEVC level_idc patched \(original) -> \(maxLevel) (\(Double(original) / 30)  -> 5.1)")
        }

        if patchParameterSetLevels(&bytes, hvcCPayload: payload, maxLevel: maxLevel, logger: logger) {
            didPatch = true
        }

        return didPatch ? Data(bytes) : nil
    }

    /// Finds the true `hvcC` box, not just a coincidental 4-byte match. Every
    /// MP4 box is preceded by a big-endian size covering itself, so a real
    /// `hvcC` tag at index `i` must have a plausible size at `i-4` (it fits
    /// within the remaining data and is bigger than the 8-byte box header) --
    /// a random "hvcC" byte sequence turning up inside an unrelated binary
    /// table (e.g. stco/stsz) won't also have a valid size in front of it.
    private static func hvcCPayloadIndex(_ bytes: [UInt8]) -> Int? {
        let tag: [UInt8] = Array("hvcC".utf8)
        guard bytes.count >= tag.count + 4 else { return nil }
        for i in 4...(bytes.count - tag.count)
        where bytes[i] == tag[0] && bytes[i + 1] == tag[1] && bytes[i + 2] == tag[2] && bytes[i + 3] == tag[3] {
            let boxStart = i - 4
            let size = (UInt32(bytes[boxStart]) << 24) | (UInt32(bytes[boxStart + 1]) << 16)
                | (UInt32(bytes[boxStart + 2]) << 8) | UInt32(bytes[boxStart + 3])
            guard size > 8, boxStart + Int(size) <= bytes.count else { continue }
            return i + tag.count
        }
        return nil
    }

    private static func patchParameterSetLevels(
        _ bytes: inout [UInt8],
        hvcCPayload: Int,
        maxLevel: UInt8,
        logger: (String) -> Void
    ) -> Bool {
        let numArraysIndex = hvcCPayload + 22
        guard numArraysIndex < bytes.count else { return false }
        var cursor = numArraysIndex + 1
        var didPatch = false

        for _ in 0..<Int(bytes[numArraysIndex]) {
            guard cursor + 2 < bytes.count else { break }
            let nalType = bytes[cursor] & 0x3f
            let numNalus = Int(bytes[cursor + 1]) << 8 | Int(bytes[cursor + 2])
            cursor += 3

            for _ in 0..<numNalus {
                guard cursor + 1 < bytes.count else { return didPatch }
                let length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
                let nalStart = cursor + 2
                guard length > 0, nalStart + length <= bytes.count else { return didPatch }

                let profileTierLevelOffset: Int?
                switch nalType {
                case 32: profileTierLevelOffset = 6
                case 33: profileTierLevelOffset = 3
                default: profileTierLevelOffset = nil
                }

                if let profileTierLevelOffset,
                   let levelIndex = rawIndexOfRBSPByte(
                       bytes,
                       nalStart: nalStart,
                       length: length,
                       rbspTarget: profileTierLevelOffset + 11
                   ),
                   bytes[levelIndex] > maxLevel {
                    let original = bytes[levelIndex]
                    bytes[levelIndex] = maxLevel
                    didPatch = true
                    logger("HEVC \(nalType == 32 ? "VPS" : "SPS") level_idc patched \(original) -> \(maxLevel)")
                }

                cursor = nalStart + length
            }
        }
        return didPatch
    }

    private static func rawIndexOfRBSPByte(_ bytes: [UInt8], nalStart: Int, length: Int, rbspTarget: Int) -> Int? {
        var rbspIndex = 2
        var zeroRun = 0
        var i = nalStart + 2
        let end = nalStart + length

        while i < end {
            let byte = bytes[i]
            if zeroRun >= 2 && byte == 0x03 {
                zeroRun = 0
                i += 1
                continue
            }
            if rbspIndex == rbspTarget { return i }
            zeroRun = byte == 0 ? zeroRun + 1 : 0
            rbspIndex += 1
            i += 1
        }
        return nil
    }

    // MARK: HDR metadata correction

    /// The source declares PQ/HDR10 color (transfer_characteristics=16,
    /// BT.2020 primaries) in the SPS but ships no Mastering Display Colour
    /// Volume or Content Light Level SEI messages -- both required by
    /// Apple's HLS Authoring Spec for HDR10 content. AVFoundation is
    /// stricter than other decoders about this combination and rejects the
    /// item outright; other platforms' more permissive decoders don't care.
    /// Inject both SEI messages (reasonable defaults: 1000-nit mastering
    /// display, matching MaxCLL/MaxFALL) as a prefix SEI NAL ahead of the
    /// first sample's keyframe, in the one CMAF fragment (moof+mdat) this is
    /// called on. Returns nil (untouched) if the segment isn't in a shape
    /// this can safely patch -- never partially rewrites a fragment.
    private static func injectHDRMetadataSEI(_ data: Data, logger: (String) -> Void = { _ in }) -> Data? {
        var bytes = [UInt8](data)

        func find(_ tag: String, from: Int) -> Int? {
            let needle = Array(tag.utf8)
            guard from >= 0, bytes.count >= needle.count else { return nil }
            var i = from
            while i <= bytes.count - needle.count {
                if bytes[i] == needle[0], bytes[i + 1] == needle[1], bytes[i + 2] == needle[2], bytes[i + 3] == needle[3] {
                    return i - 4 // box header (size field) start
                }
                i += 1
            }
            return nil
        }
        func u32(_ i: Int) -> Int { (Int(bytes[i]) << 24) | (Int(bytes[i + 1]) << 16) | (Int(bytes[i + 2]) << 8) | Int(bytes[i + 3]) }
        func setU32(_ i: Int, _ v: Int) {
            bytes[i] = UInt8((v >> 24) & 0xff); bytes[i + 1] = UInt8((v >> 16) & 0xff)
            bytes[i + 2] = UInt8((v >> 8) & 0xff); bytes[i + 3] = UInt8(v & 0xff)
        }

        guard let moofOff = find("moof", from: 0),
              let trafOff = find("traf", from: moofOff + 8),
              let trunOff = find("trun", from: trafOff + 8),
              let mdatOff = find("mdat", from: trunOff + 8) else { return nil }

        let flags = (Int(bytes[trunOff + 9]) << 16) | (Int(bytes[trunOff + 10]) << 8) | Int(bytes[trunOff + 11])
        guard flags & 0x200 != 0 else { return nil } // no per-sample size field -- can't safely resize one sample

        var p = trunOff + 16
        if flags & 0x000001 != 0 { p += 4 } // data-offset-present
        if flags & 0x000004 != 0 { p += 4 } // first-sample-flags-present
        let hasDuration = flags & 0x000100 != 0
        let sizeOff = p + (hasDuration ? 4 : 0)
        guard sizeOff + 4 <= bytes.count else { return nil }
        let firstSampleSize = u32(sizeOff)

        let sampleStart = mdatOff + 8
        guard sampleStart + firstSampleSize <= bytes.count else { return nil }

        // Walk length-prefixed NALs (4-byte length, per hvcC lengthSizeMinusOne=3)
        // in the first sample to find the first VCL NAL (the keyframe).
        var i = sampleStart
        var insertAt: Int?
        while i + 4 < sampleStart + firstSampleSize {
            let nalLen = u32(i)
            let nalType = (bytes[i + 4] >> 1) & 0x3f
            if nalType <= 31 { insertAt = i; break }
            i += 4 + nalLen
        }
        guard let insertAt else { return nil }

        // Build the SEI NAL: mastering_display_colour_volume (type 137) with
        // typical Rec.2020/1000-nit defaults, then content_light_level_info
        // (type 144) with matching MaxCLL/MaxFALL -- both byte-aligned so no
        // bitstream-level packing is needed, just emulation prevention.
        var payload: [UInt8] = []
        let primaries: [(UInt16, UInt16)] = [(35400, 14600), (8500, 39850), (6550, 2300)]
        let white: (UInt16, UInt16) = (15635, 16450)
        payload += [137, 24]
        for (x, y) in primaries { payload += [UInt8(x >> 8), UInt8(x & 0xff), UInt8(y >> 8), UInt8(y & 0xff)] }
        payload += [UInt8(white.0 >> 8), UInt8(white.0 & 0xff), UInt8(white.1 >> 8), UInt8(white.1 & 0xff)]
        let maxLum: UInt32 = 10_000_000, minLum: UInt32 = 50
        payload += [UInt8(maxLum >> 24), UInt8((maxLum >> 16) & 0xff), UInt8((maxLum >> 8) & 0xff), UInt8(maxLum & 0xff)]
        payload += [UInt8(minLum >> 24), UInt8((minLum >> 16) & 0xff), UInt8((minLum >> 8) & 0xff), UInt8(minLum & 0xff)]
        payload += [144, 4, 0x03, 0xe8, 0x01, 0x90] // maxCLL=1000, maxFALL=400
        payload += [0x80] // rbsp_trailing_bits (already byte-aligned)

        var rbsp: [UInt8] = []
        var zeroRun = 0
        for b in payload {
            if zeroRun >= 2, b <= 3 { rbsp.append(0x03); zeroRun = 0 }
            rbsp.append(b)
            zeroRun = b == 0 ? zeroRun + 1 : 0
        }
        let seiNAL: [UInt8] = [0x4E, 0x01] + rbsp // nal_unit_type=39 (prefix SEI)
        let delta = 4 + seiNAL.count
        var inserted = [UInt8](repeating: 0, count: 4)
        inserted[0] = UInt8((seiNAL.count >> 24) & 0xff); inserted[1] = UInt8((seiNAL.count >> 16) & 0xff)
        inserted[2] = UInt8((seiNAL.count >> 8) & 0xff); inserted[3] = UInt8(seiNAL.count & 0xff)
        inserted += seiNAL

        bytes.insert(contentsOf: inserted, at: insertAt)
        setU32(sizeOff, firstSampleSize + delta)
        setU32(mdatOff, u32(mdatOff) + delta)

        logger("HDR SEI injected: mastering-display + content-light-level (+\(delta) bytes)")
        return Data(bytes)
    }

    // MARK: Master playlist variant filtering

    /// Reduces a master playlist to the single `#EXT-X-STREAM-INF` entry whose
    /// RESOLUTION height is closest to `height` (preferring <= over >). Media
    /// playlists and masters without parseable resolutions pass through intact.
    static func filterMaster(_ data: Data, toHeight height: Int, logger: (String) -> Void = { _ in }) -> Data {
        guard let text = String(data: data, encoding: .utf8), text.contains("#EXT-X-STREAM-INF") else {
            return data
        }
        var lines = text.components(separatedBy: "\n")

        // Collect (lineIndex, height) for every variant entry.
        var variants: [(tagIndex: Int, height: Int)] = []
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            guard let range = line.range(of: #"RESOLUTION=\d+x(\d+)"#, options: .regularExpression),
                  let h = Int(line[range].split(separator: "x").last ?? "") else { continue }
            variants.append((index, h))
        }
        guard variants.count > 1 else { return data }

        // Closest height, preferring the largest one that fits under the target
        // so "720p" never silently serves 1080p.
        let chosen = variants.filter { $0.height <= height }.max { $0.height < $1.height }
            ?? variants.min { $0.height < $1.height }!
        // The 4K rendition is actually encoded as HEVC but the playlist mislabels it
        // as avc1 (H.264) — AVPlayer configures its decoder off this label, gets HEVC
        // sample data instead, and fails with CoreMediaErrorDomain -12927. Rather than
        // guess the exact HEVC profile/level string (a wrong guess fails the same way),
        // strip CODECS entirely so AVPlayer falls back to sniffing the init segment,
        // which does correctly declare hvc1.
        if chosen.height >= 2160, lines[chosen.tagIndex].contains("avc1") {
            lines[chosen.tagIndex] = lines[chosen.tagIndex].replacingOccurrences(
                of: #",?CODECS="[^"]*""#,
                with: "",
                options: .regularExpression
            )
        }
        // Tried adding VIDEO-RANGE=PQ here (Apple's HLS Authoring Spec requires
        // it on HDR10 variants) alongside the SEI injection below, but it made
        // AVFoundation stall indefinitely before ever requesting the media
        // playlist -- confirmed via request-lifecycle logging that nothing
        // else was ever asked of the proxy, so the stall is inside AVFoundation
        // itself (probably HDR display-capability negotiation), not our
        // server. Pulled back out to isolate it from the SEI-injection fix.

        logger("FILTER master: kept \(chosen.height)p of [\(variants.map { "\($0.height)p" }.joined(separator: ", "))] for target \(height)p — chosen variant tag: \(lines[chosen.tagIndex])")

        // Drop every other variant's tag line + its following URI line.
        var dropped = Set<Int>()
        for variant in variants where variant.tagIndex != chosen.tagIndex {
            dropped.insert(variant.tagIndex)
            var next = variant.tagIndex + 1
            // The URI is the next non-comment, non-empty line.
            while next < lines.count {
                let trimmed = lines[next].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { next += 1; continue }
                dropped.insert(next)
                break
            }
        }

        let kept = lines.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
        return Data(kept.joined(separator: "\n").utf8)
    }

    // MARK: Content sniffing

    /// Infer the real media type from the bytes, ignoring the disguised
    /// extension: 0x47 sync byte => MPEG-TS, `ftyp`/`styp`/`moof` box => fMP4.
    private func segmentMimeType(for data: Data) -> String {
        if data.first == 0x47 { return "video/mp2t" }
        if data.count >= 8 {
            let box = data.subdata(in: data.index(data.startIndex, offsetBy: 4)..<data.index(data.startIndex, offsetBy: 8))
            if box == Data("ftyp".utf8) || box == Data("styp".utf8) || box == Data("moof".utf8) {
                return "video/mp4"
            }
        }
        return "video/mp2t"
    }

    // MARK: Helpers

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 502: return "Bad Gateway"
        default: return "Status"
        }
    }

    private func log(_ message: @autoclosure () -> String) {
        if Self.verbose { print("[HLSProxy] \(message())") }
    }
}

/// In-memory LRU cache of fully-fetched segments, keyed by origin URL. Bounds
/// total bytes so long movies don't grow memory without limit. Segments are
/// immutable for a given URL, so caching is always safe; playlists are never
/// cached (they can change / carry rotating tokens).
private actor SegmentCache {
    private var storage: [String: Data] = [:]
    private var order: [String] = []   // least-recently-used first
    private var totalBytes = 0
    private let capacityBytes: Int

    init(capacityBytes: Int) {
        self.capacityBytes = capacityBytes
    }

    func data(for key: String) -> Data? {
        guard let data = storage[key] else { return nil }
        touch(key)
        return data
    }

    func store(_ data: Data, for key: String) {
        guard data.count <= capacityBytes else { return }
        if let existing = storage[key] {
            totalBytes -= existing.count
        }
        storage[key] = data
        totalBytes += data.count
        touch(key)
        evictIfNeeded()
    }

    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }

    private func evictIfNeeded() {
        while totalBytes > capacityBytes, let oldest = order.first {
            order.removeFirst()
            totalBytes -= storage[oldest]?.count ?? 0
            storage[oldest] = nil
        }
    }
}
