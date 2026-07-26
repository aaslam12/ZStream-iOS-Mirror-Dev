//
//  TestStreamCatalog.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

/// TEMPORARY: stands in for real per-episode source resolution until
/// Celeste's backend provides it. Cycles through a small set of known-good
/// public test streams so multi-episode UI (next/prev, per-episode download)
/// can be built and tested against something real.
struct StreamResponse: Decodable {
    let noReferrer: Bool
    let url: URL
    let tracks: [SubtitleTrack]
}

struct SubtitleTrack: Decodable {
    let file: URL
    let label: String
}

struct APIResponse<T: Decodable>: Decodable {
    let status: Int
    let result: T
    let error: String?
}

struct ServersResult: Decodable {
    let servers: String
    let stream: String
    let token: String
}

struct VidFastServer: Decodable {
    let data: String
}

enum ResolverError: Error {
    case noToken
    case apiError
}

enum VidFastResolver {

    private static let api = URL(string: "https://enc-dec.app/api")!

    private static var headers: [String:String] {
        [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Referer": "https://vidfast.vc/",
            "Origin": "https://vidfast.vc",
            "X-Requested-With": "XMLHttpRequest"
        ]
    }

    static func resolveMovie(
        tmdbId: Int
    ) async throws -> PlaybackSource {

        let html = try await fetchVidfastHTML(
            path: "movie/\(tmdbId)/"
        )

        let text = try extractEncryptedText(
            from: html
        )

        let serverInfo = try await fetchServerURLs(
            text: text
        )

        let servers = try await decryptServers(
            url: serverInfo.servers,
            token: serverInfo.token
        )

        guard !servers.isEmpty else {
            throw ResolverError.apiError
        }

        var lastError: Error = ResolverError.apiError
        for server in servers {
            do {
                let encryptedStream = try await fetchStream(
                    baseURL: serverInfo.stream,
                    data: server.data,
                    token: serverInfo.token
                )
                let stream = try await decryptStream(encryptedStream)
                let subtitles = stream.tracks.map { PlaybackSubtitle(label: $0.label, url: $0.file) }
                return PlaybackSource(url: stream.url, subtitles: subtitles)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }


    static func resolveEpisode(
        tmdbId: Int,
        season: Int,
        episode: Int
    ) async throws -> PlaybackSource {

        let html = try await fetchVidfastHTML(
            path: "tv/\(tmdbId)/\(season)/\(episode)/"
        )

        let text = try extractEncryptedText(from: html)

        let serverInfo = try await fetchServerURLs(text: text)

        let servers = try await decryptServers(
            url: serverInfo.servers,
            token: serverInfo.token
        )
        
        guard !servers.isEmpty else {
            throw ResolverError.apiError
        }

        var lastError: Error = ResolverError.apiError
        for server in servers {
            do {
                let encryptedStream = try await fetchStream(
                    baseURL: serverInfo.stream,
                    data: server.data,
                    token: serverInfo.token
                )
                let stream = try await decryptStream(encryptedStream)
                let subtitles = stream.tracks.map { PlaybackSubtitle(label: $0.label, url: $0.file) }
                return PlaybackSource(url: stream.url, subtitles: subtitles)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func fetchVidfastHTML(
        path: String
    ) async throws -> String {

        let url = URL(
            string: "https://vidfast.vc/\(path)"
        )!

        var request = URLRequest(url: url)

        headers.forEach {
            request.setValue(
                $1,
                forHTTPHeaderField: $0
            )
        }

        let (data, _) = try await URLSession.shared.data(
            for: request
        )

        return String(
            decoding: data,
            as: UTF8.self
        )
    }

    private static func extractEncryptedText(
        from html: String
    ) throws -> String {

        let pattern = #"\\\"(?:en|token)\\\":\\\"(.*?)\\\""#

        let regex = try NSRegularExpression(
            pattern: pattern
        )

        let range = NSRange(
            html.startIndex..<html.endIndex,
            in: html
        )

        guard let match = regex.firstMatch(
            in: html,
            range: range
        ) else {
            throw ResolverError.noToken
        }

        guard let captureRange = Range(
            match.range(at: 1),
            in: html
        ) else {
            throw ResolverError.noToken
        }

        return String(html[captureRange])
    }
    
    private static func fetchServerURLs(
        text: String
    ) async throws -> ServersResult {

        let url = api.appending(
            path: "enc-vidfast"
        )

        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(
                name: "text",
                value: text
            )
        ]

        let (data, _) = try await URLSession.shared.data(
            from: components.url!
        )

        let response = try JSONDecoder()
            .decode(
                APIResponse<ServersResult>.self,
                from: data
            )

        guard response.status == 200 else {
            print(response.error ?? "Unknown error")
            throw ResolverError.apiError
        }
        
        return response.result
    }

    
    private static func decryptServers(
        url: String,
        token: String
    ) async throws -> [VidFastServer] {

        var request = URLRequest(
            url: URL(string: url)!
        )

        request.httpMethod = "POST"

        headers.forEach {
            request.setValue(
                $1,
                forHTTPHeaderField: $0
            )
        }

        request.setValue(
            token,
            forHTTPHeaderField: "X-CSRF-Token"
        )

        let (data, _) = try await URLSession.shared.data(
            for: request
        )

        let encrypted = String(
            decoding: data,
            as: UTF8.self
        )

        return try await decrypt(
            encrypted
        )
    }

    
    private static func decrypt(
        _ text: String
    ) async throws -> [VidFastServer] {

        let url = api.appending(
            path: "dec-vidfast"
        )

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = try JSONEncoder()
            .encode([
                "text": text
            ])

        let (data, _) = try await URLSession.shared.data(
            for: request
        )

        let response = try JSONDecoder()
            .decode(
                APIResponse<[VidFastServer]>.self,
                from: data
            )

        return response.result
    }

    
    private static func fetchStream(
        baseURL: String,
        data: String,
        token: String
    ) async throws -> String {

        let url = URL(
            string: "\(baseURL)/\(data)"
        )!

        var request = URLRequest(url: url)
        
        request.httpMethod = "POST"
        
        headers.forEach {
            request.setValue(
                $1,
                forHTTPHeaderField: $0
            )
        }

        request.setValue(
            token,
            forHTTPHeaderField: "X-CSRF-Token"
        )

        let (data, _) = try await URLSession.shared.data(
            for: request
        )

        return String(
            decoding: data,
            as: UTF8.self
        )
    }

    
    private static func decryptStream(
        _ encrypted: String
    ) async throws -> StreamResponse {

        let url = api.appending(
            path: "dec-vidfast"
        )

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = try JSONEncoder()
            .encode([
                "text": encrypted
            ])

        let (data, _) = try await URLSession.shared.data(
            for: request
        )
        
        
        let jsonString = String(
            decoding: data,
            as: UTF8.self
        )

        print("decryptStream response:")
        print(jsonString)


        let response = try JSONDecoder()
            .decode(
                APIResponse<StreamResponse>.self,
                from: data
            )

        let stream = response.result

        print("========== TESTING PLAYLIST ==========")

        var request2 = URLRequest(url: stream.url)
        request2.setValue(
            "https://vidfast.vc/",
            forHTTPHeaderField: "Referer"
        )
        request2.setValue(
            "https://vidfast.vc",
            forHTTPHeaderField: "Origin"
        )
        request2.setValue(
            "Mozilla/5.0",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (playlistData, playlistResponse) =
                try await URLSession.shared.data(for: request2)

            print("Playlist HTTP:")
            print(playlistResponse)

            let playlist = String(
                decoding: playlistData,
                as: UTF8.self
            )

            print(playlist)

            let lines = playlist.components(separatedBy: "\n")

            let segmentURLs = lines.filter {
                !$0.hasPrefix("#") && !$0.isEmpty
            }

            print("Segments found:", segmentURLs.count)

            for segment in segmentURLs.prefix(5) {

                let segmentURL: URL

                if let url = URL(string: segment), url.scheme != nil {
                    segmentURL = url
                } else {
                    segmentURL = stream.url
                        .deletingLastPathComponent()
                        .appendingPathComponent(segment)
                }

                var segmentRequest = URLRequest(url: segmentURL)

                segmentRequest.setValue(
                    "https://vidfast.vc/",
                    forHTTPHeaderField: "Referer"
                )

                segmentRequest.setValue(
                    "https://vidfast.vc",
                    forHTTPHeaderField: "Origin"
                )

                segmentRequest.setValue(
                    "Mozilla/5.0",
                    forHTTPHeaderField: "User-Agent"
                )

                let (_, response) = try await URLSession.shared.data(
                    for: segmentRequest
                )

                if let http = response as? HTTPURLResponse {
                    print(segmentURL.absoluteString, http.statusCode)
                }
            }


        } catch {
            print("PLAYLIST FETCH FAILED:")
            print(error)
        }

        print("======================================")

        return stream
    }
}


enum TestStreamCatalog {
    static func source(forMovieId id: Int) async throws -> PlaybackSource {
        try await VidFastResolver.resolveMovie(tmdbId: id)
    }

    static func source(
        forEpisodeId episodeId: Int,
        tmdbId: Int,
        season: Int,
        episode: Int
    ) async throws -> PlaybackSource {
        try await VidFastResolver.resolveEpisode(
            tmdbId: tmdbId,
            season: season,
            episode: episode
        )
    }
}

