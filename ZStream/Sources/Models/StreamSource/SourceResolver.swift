//
//  SourceResolver.swift
//  ZStream
//
//  Tries a set of StreamSource/SourceInfo pairs in order, stopping at the
//  first one that succeeds.
//

import Foundation
import os
import ZStreamCore

private let logger = Logger(subsystem: "com.z-stream.app", category: "SourceResolver")

/// print() -- DiagnosticsLog captures all stdout app-wide, no need to call it directly.
private func diag(_ message: String) {
    print(message)
}

final class SourceResolver {
    /// One triable source: which StreamSource implementation owns it, and
    /// which of its SourceInfo entries to resolve.
    struct Candidate {
        let source: StreamSource
        let info: SourceInfo
    }

    private let candidates: [Candidate]
    /// A source that hasn't answered within this long almost certainly
    /// doesn't have the title (most real answers land in well under a
    /// second) — treated as a miss so the chain moves on instead of hanging.
    private let perSourceTimeout: Duration

    init(candidates: [Candidate], perSourceTimeout: Duration = .seconds(10)) {
        self.candidates = candidates
        self.perSourceTimeout = perSourceTimeout
    }

    /// A successful resolution plus which source produced it, so callers can
    /// show/remember the winning source.
    struct Resolution {
        let sourceId: String
        let success: StreamResult.Success
    }

    /// Tries every candidate, in order, stopping at the first success.
    /// `onUpdate` fires after each status transition so a caller can drive a
    /// per-source status UI.
    func resolve(
        media: MediaRequest,
        onUpdate: ([SourceResult]) -> Void = { _ in }
    ) async -> Resolution? {
        var results = candidates.map { SourceResult(id: $0.info.id, status: .idle) }
        onUpdate(results)
        diag("[Sources] resolving \(media.tmdbId) s\(media.season ?? 0)e\(media.episode ?? 0) — order: \(results.map(\.id).joined(separator: " -> "))")

        for candidate in candidates {
            mark(&results, candidate.info.id, .trying)
            onUpdate(results)
            diag("[Sources] trying \(candidate.info.id)…")

            switch await resolveWithTimeout(candidate, media: media) {
            case .success(let success):
                logger.info("\(candidate.info.id, privacy: .public) succeeded (codec: \(success.codec, privacy: .public))")
                mark(&results, candidate.info.id, .success, codec: success.codec)
                onUpdate(results)
                let host = URL(string: success.streamUrl)?.host ?? "?"
                diag("[Sources] ✔ \(candidate.info.id) succeeded — host=\(host) type=\(success.streamType) codec=\(success.codec.isEmpty ? "unknown" : success.codec) captions=\(success.captions.count) variants=\(success.variants.count)")
                return Resolution(sourceId: candidate.info.id, success: success)
            case .notFound:
                logger.notice("\(candidate.info.id, privacy: .public) not found")
                mark(&results, candidate.info.id, .failed)
                onUpdate(results)
                diag("[Sources] ✘ \(candidate.info.id) has no stream for this title — moving on")
            case .error(let message):
                logger.error("\(candidate.info.id, privacy: .public) failed: \(message, privacy: .public)")
                mark(&results, candidate.info.id, .failed)
                onUpdate(results)
                diag("[Sources] ✘ \(candidate.info.id) failed: \(message) — moving on")
            }
        }

        diag("[Sources] all sources exhausted, nothing playable")
        return nil
    }

    /// Races the source's own resolve() against `perSourceTimeout`.
    private func resolveWithTimeout(_ candidate: Candidate, media: MediaRequest) async -> StreamResult {
        await withTaskGroup(of: StreamResult.self) { group in
            group.addTask { await candidate.source.resolve(media: media, sourceId: candidate.info.id) }
            group.addTask { [perSourceTimeout] in
                try? await Task.sleep(for: perSourceTimeout)
                return .error(message: "Timed out waiting for a response")
            }
            let result = await group.next() ?? .error(message: "Timed out waiting for a response")
            group.cancelAll()
            return result
        }
    }

    private func mark(_ results: inout [SourceResult], _ id: String, _ status: SourceStatus, codec: String = "") {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].status = status
        if !codec.isEmpty {
            results[index].codec = codec
        }
    }
}
