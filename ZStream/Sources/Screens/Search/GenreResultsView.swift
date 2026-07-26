//
//  GenreResultsView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct GenreResultsView: View {
    let genreId: Int
    let genreName: String
    @EnvironmentObject var settings: AppSettings
    @State private var results: [any MediaItem] = []
    @State private var selectedReference: MediaItemReference?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(results, id: \.id) { item in
                    Button {
                        selectedReference = MediaItemReference(mediaId: item.id, mediaType: item.mediaType)
                    } label: {
                        PosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(genreName)
        .task {
            results = (try? await SearchMediaRepository(settings: settings).moviesByGenre(genreId: genreId)) ?? []
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
