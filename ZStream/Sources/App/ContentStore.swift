//
//  ContentStore.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Holds all the loaded data the app. Contains user data, profile, recently watched, bookmarks, etc...
/// Written by Boostrapper.swift and read from app Views
@MainActor
final class ContentStore: ObservableObject {
    @Published var profile: UserProfile = UserProfile(displayName: "Guest", avatarURL: nil)
    @Published var recentlyWatched: [RecentlyWatched] = []
    @Published var bookmarks: [Bookmark] = []
    @Published var movieCatalog: MovieCatalog = .empty
    @Published var tvCatalog: TVCatalog = .empty
}
