//
//  EpisodePlaybackState.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

@MainActor
final class EpisodePlaybackState: ObservableObject {
    @Published var currentEpisode: SeasonDetail.Episode?
    @Published var currentSeasonNumber: Int

    private var allEpisodesInSeason: [SeasonDetail.Episode]

    /// Represents "no episode context" — used for movies and raw downloads,
    /// so PlayerContent never needs to handle an Optional EpisodePlaybackState.
    static var none: EpisodePlaybackState { EpisodePlaybackState() }

    private init() {
        currentSeasonNumber = 0
        allEpisodesInSeason = []
        currentEpisode = nil
    }

    init(seasonNumber: Int, episodes: [SeasonDetail.Episode], startingAt episode: SeasonDetail.Episode) {
        currentSeasonNumber = seasonNumber
        allEpisodesInSeason = episodes
        currentEpisode = episode
    }

    var hasNext: Bool {
        currentIndex.map { $0 < allEpisodesInSeason.count - 1 } ?? false
    }

    var hasPrevious: Bool {
        currentIndex.map { $0 > 0 } ?? false
    }

    private var currentIndex: Int? {
        guard let currentEpisode else { return nil }
        return allEpisodesInSeason.firstIndex { $0.id == currentEpisode.id }
    }

    func playNext() {
        guard let index = currentIndex, index < allEpisodesInSeason.count - 1 else { return }
        currentEpisode = allEpisodesInSeason[index + 1]
    }

    func playPrevious() {
        guard let index = currentIndex, index > 0 else { return }
        currentEpisode = allEpisodesInSeason[index - 1]
    }
}
