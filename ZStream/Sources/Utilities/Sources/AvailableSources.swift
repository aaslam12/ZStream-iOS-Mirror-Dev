//
//  AvailableSources.swift
//  ZStream
//
//  The list of StreamSource implementations SourceResolver tries, in order.
//  Add or remove sources here. The native resolvers (Artemis/Aurora/Tokyo/
//  Stellar/Nesterov/Aspera/Aphrodite) live in the private ZStreamNativeSources
//  package/framework — see NativeSources.all.
//

import ZStreamCore
import ZStreamNativeSources

enum AvailableSources {
    static let all: [StreamSource] = {
        var sources = NativeSources.all
        sources.insert(MagnoliaSource(), at: 5) // preserves original order: ...Nesterov, Magnolia, Aspera, Aphrodite
        return sources
        // VidLinkSource() removed on real builds. only used for debug builds
    }()

    /// Every (StreamSource, SourceInfo) pair currently registered, in the
    /// catalog's built-in default order.
    static func allCandidates() -> [SourceResolver.Candidate] {
        all.flatMap { source in
            source.availableSources().map { SourceResolver.Candidate(source: source, info: $0) }
        }
    }

    /// Candidates reordered per the user's saved preference (`AppSettings.sourceOrder`,
    /// a list of SourceInfo ids). Sources missing from `preference` — e.g. ones
    /// added to the catalog after the order was saved — keep their catalog order
    /// and sort after every preferred one. If `lastUsedSourceId` is provided, that
    /// source is promoted to the very front, ahead of everything else.
    static func orderedCandidates(preference: [String], prioritizing lastUsedSourceId: String? = nil) -> [SourceResolver.Candidate] {
        var ordered = allCandidates().sorted { a, b in
            let ai = preference.firstIndex(of: a.info.id) ?? Int.max
            let bi = preference.firstIndex(of: b.info.id) ?? Int.max
            return ai < bi
        }
        if let lastUsedSourceId, let index = ordered.firstIndex(where: { $0.info.id == lastUsedSourceId }), index != 0 {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return ordered
    }

    /// `preference` with unknown ids dropped and any missing catalog ids
    /// appended at the end — used to seed the reorder screen with a complete,
    /// stale-free list regardless of what's actually been saved.
    static func normalizedOrder(_ preference: [String]) -> [String] {
        let allIds = allCandidates().map(\.info.id)
        let known = preference.filter { allIds.contains($0) }
        let missing = allIds.filter { !known.contains($0) }
        return known + missing
    }
}
