//
//  ImageCarousel.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

struct ImageCarousel: View {
    var onSelect: ((any MediaItem) -> Void)? = nil
    var onPlay: ((any MediaItem) -> Void)? = nil
    var onLoadMore: (() async -> [any MediaItem])? = nil

    @State private var loadedItems: [any MediaItem]
    @State private var selection = 0
    @State private var isLoadingMore = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var lastInteractionTime: Date = .distantPast

    init(
        items: [any MediaItem],
        onSelect: ((any MediaItem) -> Void)? = nil,
        onPlay: ((any MediaItem) -> Void)? = nil,
        onLoadMore: (() async -> [any MediaItem])? = nil
    ) {
        _loadedItems = State(initialValue: Array(items.prefix(6)))
        self.onSelect = onSelect
        self.onPlay = onPlay
        self.onLoadMore = onLoadMore
    }

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                ForEach(Array(loadedItems.enumerated()), id: \.offset) { index, item in
                    HeroSlide(
                        item: item,
                        size: geo.size,
                        onPlay: { onPlay?(item) },
                        onInfo: { onSelect?(item) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .onChange(of: selection) { _, newValue in
                lastInteractionTime = Date()
                Task { await maybeLoadMore(currentIndex: newValue) }
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.5)
        .ignoresSafeArea(edges: .top)
        .onAppear { startAutoAdvance() }
        .onDisappear { autoAdvanceTask?.cancel() }
    }

    private func startAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, !loadedItems.isEmpty else { return }

                let elapsed = Date().timeIntervalSince(lastInteractionTime)
                guard elapsed >= 5 else { continue }

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        selection = (selection + 1) % loadedItems.count
                    }
                    lastInteractionTime = Date()
                }
            }
        }
    }

    private func maybeLoadMore(currentIndex: Int) async {
        guard let onLoadMore, !isLoadingMore else { return }
        guard currentIndex >= loadedItems.count - 2 else { return }

        isLoadingMore = true
        let newItems = await onLoadMore()
        let existingKeys = Set(loadedItems.map { "\($0.mediaType.rawValue)-\($0.id)" })
        let deduped = newItems.filter { !existingKeys.contains("\($0.mediaType.rawValue)-\($0.id)") }
        loadedItems.append(contentsOf: deduped)
        isLoadingMore = false
    }
}

private struct HeroSlide: View {
    let item: any MediaItem
    let size: CGSize
    let onPlay: () -> Void
    let onInfo: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The backdrop plus its legibility scrim are masked to fade to
            // transparent at the bottom, so the poster dissolves into whatever
            // app background sits behind it — matching by revealing it directly
            // rather than trying to guess a matching color.
            Button(action: onInfo) {
                FadeInImage(url: item.backdropURL)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            }
            .buttonStyle(.plain)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.80),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(item.displayTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                metaRow

                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .frame(width: size.width * 0.75, alignment: .leading)
                }

                buttonRow
            }
            .padding(24)
        }
        .frame(width: size.width, height: size.height)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            if item.isUnreleased {
                Text("Unreleased")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.15), in: Capsule())
            }

            if item.rating > 0 {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(String(format: "%.1f", item.rating))
            } else {
                Image(systemName: "star.slash").foregroundStyle(.white.opacity(0.6))
                Text("No Ratings")
            }

            if let year = item.releaseYear {
                Text("•")
                Text(String(year))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.9))
    }

    private var buttonRow: some View {
        Button(action: onPlay) {
            Label(
                item.isUnreleased ? "Notify Me!" : "Watch",
                systemImage: item.isUnreleased ? "bell.fill" : "play.fill"
            )
            .font(.subheadline.bold())
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(.white)
        .foregroundStyle(.black)
        .controlSize(.large)
        .modifier(OptionalGlass())
        .padding(.top, 10)
        .padding(.bottom, 40)
    }

    private struct OptionalGlass: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.clear.interactive(), in: .rect(cornerRadius: 10))
            } else {
                content
            }
        }
    }
}
