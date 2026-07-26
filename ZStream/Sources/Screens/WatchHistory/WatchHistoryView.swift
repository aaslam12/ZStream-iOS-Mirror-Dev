//
//  WatchHistoryView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct WatchHistoryView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var items: [WatchHistoryEntry] = []
    @State private var isLoading = true
    @State private var detailReference: MediaItemReference?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if items.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { entry in
                    Button {
                        if let ref = entry.reference { detailReference = ref }
                    } label: {
                        WatchHistoryRow(entry: entry, accent: settings.theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ThemeBackground(theme: settings.theme))
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $detailReference) { ref in
            MediaItemDialog(reference: ref, settings: settings, onNavigate: { detailReference = $0 })
                .id(ref.id)
        }
    }

    private func load() async {
        isLoading = true
        items = await WatchHistoryService.fetch()
        isLoading = false
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No Watch History")
                .font(.headline)
            Text("Titles you watch will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct WatchHistoryRow: View {
    let entry: WatchHistoryEntry
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            FadeInImage(url: entry.posterURL)
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                if entry.completed {
                    Label("Watched", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(accent)
                } else if entry.progress > 0 {
                    ProgressView(value: entry.progress)
                        .tint(accent)
                }

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model + service

/// A normalized watch-history entry the UI renders.
struct WatchHistoryEntry: Identifiable {
    let id: String
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let posterURL: URL?
    let progress: Double
    let completed: Bool
    let subtitle: String?

    var reference: MediaItemReference? {
        MediaItemReference(mediaId: tmdbId, mediaType: mediaType)
    }
}

private enum WatchHistoryService {
    /// `GET /users/{userId}/watch-history` → normalized entries. Returns [] when
    /// signed out or on failure.
    static func fetch() async -> [WatchHistoryEntry] {
        guard let creds = CelesteSession.credentials else { return [] }
        do {
            let responses = try await fetchJSON(
                [WatchHistoryResponse].self,
                from: DefaultEndpoints.watchHistory(userId: creds.userId),
                auth: .bearer(creds.token)
            )
            return responses.compactMap { $0.toEntry() }
        } catch {
            return []
        }
    }
}

/// `GET /users/{userId}/watch-history` item. Season/episode refs are ignored;
/// only the fields the list needs are decoded (extra keys are dropped).
private struct WatchHistoryResponse: Codable {
    let tmdbId: String
    let meta: BookmarkMeta?
    let watched: String?
    let duration: String?
    let watchedAt: String?
    let completed: Bool?

    func toEntry() -> WatchHistoryEntry? {
        guard let id = Int(tmdbId) else { return nil }
        let isShow = (meta?.type == "show" || meta?.type == "tv")
        let watchedSeconds = Double(watched ?? "") ?? 0
        let totalSeconds = Double(duration ?? "") ?? 0
        let progress = totalSeconds > 0 ? min(max(watchedSeconds / totalSeconds, 0), 1) : 0

        return WatchHistoryEntry(
            id: tmdbId + "-" + (watchedAt ?? ""),
            tmdbId: id,
            mediaType: isShow ? .tv : .movie,
            title: meta?.title ?? "Title #\(tmdbId)",
            posterURL: Self.posterURL(from: meta?.poster),
            progress: progress,
            completed: completed ?? (progress >= 0.98),
            subtitle: Self.relativeDate(from: watchedAt)
        )
    }

    private static func posterURL(from poster: String?) -> URL? {
        guard let poster, !poster.isEmpty else { return nil }
        if poster.hasPrefix("http") { return URL(string: poster) }
        if poster.hasPrefix("/") { return URL(string: "https://image.tmdb.org/t/p/w200\(poster)") }
        return nil
    }

    private static func relativeDate(from iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Watched " + formatter.localizedString(for: date, relativeTo: Date())
    }
}
