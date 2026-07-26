//
//  MagnoliaSource.swift
//  ZStream
//
//  Public source: wingsdatabase.com's "yoru"/"neon" CDN providers, fronted
//  by a TMDB-mirror metadata lookup. No auth gate, no signature scheme --
//  safe to ship in the open-source app.
//

import Foundation
import ZStreamCore

private actor MagnoliaCache {
    private var entries: [String: (expires: Date, result: StreamResult.Success)] = [:]
    private let ttl: TimeInterval = 5 * 60

    func get(_ key: String) -> StreamResult.Success? {
        guard let entry = entries[key], entry.expires > Date() else { return nil }
        return entry.result
    }

    func set(_ key: String, _ result: StreamResult.Success) {
        entries[key] = (Date().addingTimeInterval(ttl), result)
    }
}

struct MagnoliaSource: StreamSource {
    let version = 1

    private static let base = "https://api.wingsdatabase.com"
    private static let db = "https://db.wingsdatabase.com"
    private static let referer = "https://player.videasy.to/"
    private static let origin = "https://www.videasy.to"
    private static let providerTimeout: TimeInterval = 4
    private static let cache = MagnoliaCache()

    private struct Pick {
        let url: String
        let quality: String
        let type: String // "hls" or "dash"
    }

    func availableSources() -> [SourceInfo] {
        [SourceInfo(id: "magnolia", displayName: "Magnolia")]
    }

    func resolve(media: MediaRequest, sourceId: String) async -> StreamResult {
        guard sourceId == "magnolia" else { return .notFound }

        let cacheKey = "\(media.tmdbId):\(media.season ?? 0):\(media.episode ?? 0)"
        if let cached = await Self.cache.get(cacheKey) {
            return .success(cached)
        }

        do {
            guard let result = try await resolveUncached(media: media) else {
                return .notFound
            }
            await Self.cache.set(cacheKey, result)
            return .success(result)
        } catch {
            return .error(message: "\(error)")
        }
    }

    // MARK: - Resolution

    private func resolveUncached(media: MediaRequest) async throws -> StreamResult.Success? {
        let show = media.type == .show
        let id = media.tmdbId
        guard let mediaIdUInt32 = UInt32(id) else { return nil }

        let headers = ["Referer": Self.referer, "Accept": "application/json"]

        let metaURL = "\(Self.db)/3/\(show ? "tv" : "movie")/\(id)?append_to_response=external_ids&language=en"
        guard let meta = try await getJSON(metaURL, headers: headers) else { return nil }

        let title = nonEmptyString(meta[show ? "name" : "title"]) ?? nonEmptyString(meta[show ? "original_name" : "original_title"])
        guard let title else { return nil }

        let date = meta[show ? "first_air_date" : "release_date"] as? String ?? ""
        let externalIds = meta["external_ids"] as? [String: Any]
        let imdb = externalIds?["imdb_id"] as? String ?? ""
        let totalSeasons = (meta["number_of_seasons"] as? Int).map(String.init) ?? ""

        let seedURL = "\(Self.base)/seed?mediaId=\(id)"
        guard let seedJSON = try await getJSON(seedURL, headers: headers),
              let seed = nonEmptyString(seedJSON["seed"]) else { return nil }

        var query = "title=\(urlEncode(title))&mediaType=\(show ? "tv" : "movie")"
        query += "&year=\(date.count >= 4 ? String(date.prefix(4)) : "")"
        query += "&episodeId=\(show ? String(media.episode ?? 1) : "1")"
        query += "&seasonId=\(show ? String(media.season ?? 1) : "1")"
        query += "&tmdbId=\(id)&imdbId=\(urlEncode(imdb))"
        if show { query += "&totalSeasons=\(totalSeasons)" }
        query += "&enc=2&seed=\(urlEncode(seed))"

        // Strictly sequential: yoru, then neon. Not concurrent.
        let yoruPicks = await fetchProvider(
            path: "/cdn/sources-with-title", query: query, headers: headers,
            seed: seed, mediaId: mediaIdUInt32, isYoru: true
        )
        let neonPicks = await fetchProvider(
            path: "/neon2/sources-with-title", query: query, headers: headers,
            seed: seed, mediaId: mediaIdUInt32, isYoru: false
        )

        var finals: [(id: String, name: String, url: String, type: String)] = []

        let yoruValid = yoruPicks
            .filter { $0.type == "hls" }
            .sorted { yoruRank($0.quality) < yoruRank($1.quality) }
        if !yoruValid.isEmpty {
            finals.append(("magnolia-astral", "Astral", buildYoruMaster(yoruValid), "hls"))
        }

        if let neonPick = neonPicks.first(where: { $0.type == "hls" }) ?? neonPicks.first(where: { $0.type == "dash" }) {
            finals.append(("magnolia-neon", "Neon", neonPick.url, neonPick.type))
        }

        guard !finals.isEmpty else { return nil }

        let cdnHeaders = ["Referer": Self.referer, "Origin": Self.origin]

        let variants = finals.map {
            StreamResult.Variant(
                id: $0.id,
                name: $0.name,
                quality: "",
                codec: "",
                tag: "",
                streamUrl: $0.url,
                streamType: $0.type,
                headers: cdnHeaders
            )
        }

        return StreamResult.Success(
            streamUrl: finals[0].url,
            streamType: finals[0].type,
            captions: [],
            headers: cdnHeaders,
            codec: "",
            variants: variants,
            skipProbe: true
        )
    }

    // MARK: - Provider fetch

    private func fetchProvider(
        path: String,
        query: String,
        headers: [String: String],
        seed: String,
        mediaId: UInt32,
        isYoru: Bool
    ) async -> [Pick] {
        guard let url = URL(string: "\(Self.base)\(path)?\(query)") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: Self.providerTimeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        var body = data
        if let first = body.first, first != UInt8(ascii: "{"), first != UInt8(ascii: "[") {
            guard let text = String(data: body, encoding: .utf8),
                  let decrypted = MagnoliaCipher.decrypt(payload: text, seed: seed, mediaId: mediaId) else {
                return []
            }
            body = decrypted
        }

        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let sources = root["sources"] as? [[String: Any]] else {
            return []
        }

        var picks: [Pick] = []
        for item in sources {
            guard let url = nonEmptyString(item["url"]) else { continue }
            let quality = (item["quality"] as? String) ?? ""

            if isYoru {
                // /cdn/ (yoru) is video-only by construction and carries no "type" field, with
                // a URL that never contains ".m3u8" -- quality alone is enough to trust an entry.
                picks.append(Pick(url: url, quality: quality, type: "hls"))
                continue
            }

            let lowURL = url.lowercased()
            let kind = ((item["type"] as? String) ?? "").lowercased()
            if lowURL.contains(".m3u8") || kind == "m3u8" || kind == "hls" {
                picks.append(Pick(url: url, quality: quality, type: "hls"))
            } else if lowURL.contains(".mpd") || kind == "dash" || kind == "mpd" {
                picks.append(Pick(url: url, quality: quality, type: "dash"))
            }
        }
        return picks
    }

    // MARK: - yoru master playlist synthesis

    /// yoru hands back one standalone media playlist per resolution instead of a single
    /// adaptive master -- wrapping them in a synthetic #EXT-X-STREAM-INF master here lets
    /// the player's own track selector expose them as a native quality ladder.
    private func buildYoruMaster(_ picks: [Pick]) -> String {
        var m3u8 = "#EXTM3U\n#EXT-X-VERSION:3\n"
        for pick in picks {
            let (resolution, bandwidth) = yoruResolutionTag(pick.quality)
            m3u8 += "#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth)"
            if let resolution {
                m3u8 += ",RESOLUTION=\(resolution)"
            }
            m3u8 += "\n\(pick.url)\n"
        }
        let base64 = Data(m3u8.utf8).base64EncodedString()
        return "data:application/vnd.apple.mpegurl;base64,\(base64)"
    }

    private func yoruResolutionTag(_ quality: String) -> (String?, Int) {
        switch quality {
        case "2160p", "4K": return ("3840x2160", 15_000_000)
        case "1080p": return ("1920x1080", 5_000_000)
        case "720p": return ("1280x720", 2_800_000)
        case "480p": return ("854x480", 1_400_000)
        case "360p": return ("640x360", 800_000)
        default: return (nil, 2_000_000)
        }
    }

    private func yoruRank(_ quality: String) -> Int {
        switch quality {
        case "4K", "2160p": return 0
        case "1080p": return 1
        case "720p": return 2
        case "480p": return 3
        case "360p": return 4
        default: return 99 // unrecognized labels sort last, not dropped
        }
    }

    // MARK: - Helpers

    private func getJSON(_ urlString: String, headers: [String: String]) async throws -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }
}
