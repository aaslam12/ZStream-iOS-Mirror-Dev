//
//  SearchScreen.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/16/26.
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState

    @State private var genreTiles: [GenreTile] = GenreMap.all.map { id, name in
        GenreTile(id: id, name: name, imageName: GenreImages.assetName(for: id), gradient: GenreColors.gradient(for: id))
    }
    @State private var query: String = ""
    @State private var searchResults: [any MediaItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedReference: MediaItemReference?

    private let genreColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let resultColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    LazyVGrid(columns: genreColumns, spacing: 12) {
                        ForEach(genreTiles) { tile in
                            NavigationLink(value: tile) {
                                GenreTileView(tile: tile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                } else {
                    LazyVGrid(columns: resultColumns, spacing: 12) {
                        ForEach(searchResults, id: \.id) { item in
                            Button {
                                selectedReference = MediaItemReference(mediaId: item.id, mediaType: item.mediaType)
                            } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Movies, Shows, and More")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    let results = (try? await SearchMediaRepository(settings: settings).search(query: newValue)) ?? []
                    guard !Task.isCancelled else { return }
                    searchResults = results
                }
            }
            .navigationDestination(for: GenreTile.self) { tile in
                GenreResultsView(genreId: tile.id, genreName: tile.name)
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab != .search {
                query = ""
                searchResults = []
            }
        }
        .sheet(item: $selectedReference) { reference in
            MediaItemDialog(
                reference: reference,
                settings: settings,
                onNavigate: { newReference in
                    selectedReference = newReference
                }
            )
        }
    }
}
