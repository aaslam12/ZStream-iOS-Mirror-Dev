//
//  SearchMediaRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

struct SearchMediaRepository {
    let settings: AppSettings

    private enum Tuning {
        static let collectionMatchThreshold = 0.5   // >= half the query's words must appear in the collection name
        static let generalRelevanceGate = 0.3       // items scoring below this are filtered out entirely, not just ranked low
        static let text = 0.55
        static let recency = 0.25
        static let popularity = 0.2
        
        // genre browsing has no query text to judge relevance by, so lean
        // almost entirely on popularity + recency instead
        static let genrePopularity = 0.65
        static let genreRecency = 0.35
    }

    func search(query: String) async throws -> [any MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        async let multiTask = fetchPage(SearchResultItem.self, from: Endpoints.searchMulti(query: trimmed, settings: settings), auth: .tmdb)
        async let collectionTask = fetchPage(CollectionSearchResult.self, from: Endpoints.searchCollection(query: trimmed, settings: settings), auth: .tmdb)

        let multi = (try? await multiTask) ?? []
        let collectionResults = (try? await collectionTask) ?? []

        // Tier 1: confirmed franchise members, via TMDB's own curated collection
        var franchiseItems: [Movie] = []
        if let best = collectionResults.max(by: {
            StringSimilarity.tokenOverlapScore(title: $0.name, query: trimmed) < StringSimilarity.tokenOverlapScore(title: $1.name, query: trimmed)
        }), StringSimilarity.tokenOverlapScore(title: best.name, query: trimmed) >= Tuning.collectionMatchThreshold,
           let detail = try? await fetchJSON(CollectionDetail.self, from: Endpoints.collectionDetail(id: best.id, settings: settings), auth: .tmdb) {
            franchiseItems = detail.parts
        }

        let franchiseKeys = Set(franchiseItems.map { "movie-\($0.id)" })

        // Tier 2: everything else from plain search — but only if it clears
        // a real relevance bar. Popularity alone never gets an item in here;
        // it only orders items that already passed this gate.
        var generalItems: [(item: any MediaItem, score: Double)] = []
        for result in multi {
            let item: any MediaItem
            switch result {
            case .movie(let m): item = m
            case .tv(let t): item = t
            case .person: continue
            }

            let key = "\(item.mediaType.rawValue)-\(item.id)"
            guard !franchiseKeys.contains(key) else { continue } // already in tier 1, don't duplicate

            let relevance = max(
                StringSimilarity.textScore(title: item.displayTitle, query: trimmed),
                StringSimilarity.tokenOverlapScore(title: item.displayTitle, query: trimmed)
            )
            guard relevance >= Tuning.generalRelevanceGate else { continue } // this is what kills "Dans les secrets"-style noise

            let popularity = (item as? Movie)?.popularity ?? (item as? TVShow)?.popularity ?? 0
            let normalizedPopularity = min(popularity / 100, 1.0)
            let recency = StringSimilarity.recencyScore(releaseYear: item.releaseYear)

            let score = relevance * Tuning.text + recency * Tuning.recency + normalizedPopularity * Tuning.popularity
            generalItems.append((item, score))
        }

        // Tier 1 always comes first, ordered by popularity — matches the
        // JustWatch behavior you referenced (Fast X, Fast & Furious, Fast &
        // Furious (2009)... roughly popularity order among confirmed entries).
        let sortedFranchise = franchiseItems.sorted { $0.popularity > $1.popularity }
        let sortedGeneral = generalItems.sorted { $0.score > $1.score }.map(\.item)

        return sortedFranchise.map { $0 as any MediaItem } + sortedGeneral
    }
    
    /// No text query — used when the person taps a genre tile instead of typing.
    /// Ranked by popularity + recency only, since there's no relevance gate
    /// to apply (everything returned already belongs to the genre by definition).
    func moviesByGenre(genreId: Int) async throws -> [any MediaItem] {
        let params = DiscoverMoviesParams(sortBy: .popularityDesc, withGenres: .and([String(genreId)]))
        let movies = try await fetchPage(Movie.self, from: Endpoints.moviesBy(params, settings: settings), auth: .tmdb)

        let scored = movies.map { movie -> (item: any MediaItem, score: Double) in
            let normalizedPopularity = min(movie.popularity / 100, 1.0)
            let recency = StringSimilarity.recencyScore(releaseYear: movie.releaseYear)
            let score = normalizedPopularity * Tuning.genrePopularity + recency * Tuning.genreRecency
            return (movie, score)
        }

        return scored.sorted { $0.score > $1.score }.map(\.item)
    }
}
