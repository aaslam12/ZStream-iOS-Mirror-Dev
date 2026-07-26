//
//  MediaRowView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/16/26.
//

import SwiftUI

struct MediaRow: View {
    let title: String
    let items: [any MediaItem]
    var onSelect: ((any MediaItem) -> Void)? = nil
    var onAppearAtIndex: ((Int) -> Void)? = nil
    var isLoadingMore: Bool = false
    /// Optional long-press / 3D-touch menu for each poster.
    var menu: ((any MediaItem) -> AnyView)? = nil
    /// When true, posters animate in/out as the list changes (used by the
    /// Bookmarks and Continue Watching rows).
    var animatesItemChanges: Bool = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title3.bold()).padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                onSelect?(item)
                            } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let menu { menu(item) }
                            }
                            .transition(animatesItemChanges
                                ? .scale(scale: 0.82).combined(with: .opacity)
                                : .identity)
                            .onAppear {
                                onAppearAtIndex?(index)
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(width: 60, height: 180)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
