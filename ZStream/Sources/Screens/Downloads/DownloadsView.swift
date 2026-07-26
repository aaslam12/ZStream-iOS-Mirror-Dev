//
//  DownloadsView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/16/26.
//

import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var contentStore: ContentStore
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings

    @State private var selectedRecord: DownloadRecord?
    @State private var selectedShow: ShowGroup?
    @State private var detailReference: MediaItemReference?
    @State private var isPresentingStorageDetail = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if manager.activeDownloads.isEmpty && manager.completedDownloads.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        StorageBar(
                            usedBytes: manager.totalStorageUsed,
                            freeBytes: DownloadStorage.deviceCapacity().free,
                            accent: settings.theme.accent,
                            onInfoTap: { isPresentingStorageDetail = true }
                        )
                        .padding(.horizontal)

                        if !manager.activeDownloads.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Downloading").font(.title3.bold()).padding(.horizontal)
                                ForEach(manager.activeDownloads) { item in
                                    DownloadingRow(
                                        item: item,
                                        onCancel: { manager.cancel(id: item.id) },
                                        onPause: { manager.pauseDownload(id: item.id) },
                                        onResume: { manager.resumeDownload(id: item.id) }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if !manager.completedDownloads.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Downloaded").font(.title3.bold()).padding(.horizontal)
                                LazyVGrid(columns: columns, spacing: 16) {
                                    // Movies show individually; TV episodes are
                                    // grouped into one card per show.
                                    ForEach(movieRecords) { record in
                                        DownloadedCard(
                                            record: record,
                                            onPlay: { selectedRecord = record },
                                            onDelete: { Task { await manager.delete(id: record.id) } },
                                            onDetails: { detailReference = reference(for: record) }
                                        )
                                    }

                                    ForEach(showGroups) { group in
                                        DownloadedShowCard(
                                            group: group,
                                            onOpen: { selectedShow = group },
                                            onDetails: { detailReference = group.reference },
                                            onDeleteAll: {
                                                Task {
                                                    for record in group.records {
                                                        await manager.delete(id: record.id)
                                                    }
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.top)
                }
            }
            .background(ThemeBackground(theme: settings.theme))
            .navigationTitle("Downloads")
            .task {
                await manager.load()
            }
            .fullScreenCover(item: $selectedRecord) { record in
                PlayerView(
                    source: PlaybackSource(url: record.resolvedFileURL),
                    reference: reference(for: record),
                    isOffline: true
                )
            }
            .navigationDestination(item: $selectedShow) { group in
                DownloadedSeasonView(
                    mediaId: group.mediaId,
                    showTitle: group.title,
                    onPlay: { record in selectedRecord = record }
                )
            }
            .sheet(item: $detailReference) { ref in
                MediaItemDialog(
                    reference: ref,
                    settings: settings,
                    onNavigate: { detailReference = $0 }
                )
                .id(ref.id)
            }
            .navigationDestination(isPresented: $isPresentingStorageDetail) {
                StorageDetailView(
                    records: manager.completedDownloads,
                    activeDownloads: manager.activeDownloads,
                    onDelete: { id in Task { await manager.delete(id: id) } }
                )
            }
        }
    }

    // MARK: - Grouping

    private var movieRecords: [DownloadRecord] {
        manager.completedDownloads
            .filter { $0.mediaType == .movie }
    }

    private var showGroups: [ShowGroup] {
        let episodes = manager.completedDownloads.filter { $0.mediaType == .tv }
        return Dictionary(grouping: episodes, by: { $0.mediaId })
            .map { ShowGroup(mediaId: $0.key, records: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func reference(for record: DownloadRecord) -> MediaItemReference {
        MediaItemReference(mediaId: record.mediaId, mediaType: record.mediaType)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 120)
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Downloads Yet")
                .font(.headline)
            Text("Movies and shows you download will appear here, ready to watch offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
        }
    }
}

// MARK: - Show grouping model

/// All downloaded episodes of one TV show, collapsed into a single entry.
struct ShowGroup: Identifiable, Hashable {
    let mediaId: Int
    let records: [DownloadRecord]

    var id: Int { mediaId }
    var title: String { records.first?.showDisplayTitle ?? "" }
    var posterURL: URL? { records.first?.posterURL }
    var episodeCount: Int { records.count }
    var totalBytes: Int64 { records.reduce(0) { $0 + $1.fileSizeBytes } }
    var reference: MediaItemReference { MediaItemReference(mediaId: mediaId, mediaType: .tv) }

    static func == (lhs: ShowGroup, rhs: ShowGroup) -> Bool { lhs.mediaId == rhs.mediaId }
    func hash(into hasher: inout Hasher) { hasher.combine(mediaId) }
}

// MARK: - Show card (one per grouped TV show)

private struct DownloadedShowCard: View {
    let group: ShowGroup
    let onOpen: () -> Void
    let onDetails: () -> Void
    let onDeleteAll: () -> Void

    @State private var deleteScale: CGFloat = 1
    @State private var deleteOpacity: Double = 1

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    FadeInImage(url: group.posterURL)
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("\(group.episodeCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue, in: Capsule())
                        .padding(6)
                }

                Text(group.title).font(.caption.bold()).lineLimit(1).frame(width: 110, alignment: .leading)
                Text(episodesSummary).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(deleteScale)
        .opacity(deleteOpacity)
        .contextMenu {
            Button(action: onDetails) {
                Label("Details", systemImage: "info.circle")
            }

            Button(role: .destructive, action: animateDeleteAll) {
                Label("Delete All", systemImage: "trash")
            }
        }
    }

    /// Same "pop then implode" as DownloadedCard, before actually removing
    /// every episode in the group.
    private func animateDeleteAll() {
        withAnimation(.easeOut(duration: 0.12)) {
            deleteScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.22)) {
                deleteScale = 0.01
                deleteOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onDeleteAll()
            }
        }
    }

    private var episodesSummary: String {
        let count = group.episodeCount
        let size = ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file)
        return "\(count) episode\(count == 1 ? "" : "s") • \(size)"
    }
}

// MARK: - Episode list for one show

struct DownloadedSeasonView: View {
    let mediaId: Int
    let showTitle: String
    let onPlay: (DownloadRecord) -> Void

    // Observe the manager directly so deleting an episode updates this list
    // immediately (rather than only after leaving and re-entering the view).
    @EnvironmentObject private var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var records: [DownloadRecord] {
        manager.completedDownloads
            .filter { $0.mediaType == .tv && $0.mediaId == mediaId }
    }

    /// Season numbers present in the downloads, ascending.
    private var seasons: [Int] {
        Set(records.map { $0.seasonNumber ?? 0 }).sorted()
    }

    private func episodes(inSeason season: Int) -> [DownloadRecord] {
        records
            .filter { ($0.seasonNumber ?? 0) == season }
            .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    var body: some View {
        List {
            ForEach(seasons, id: \.self) { season in
                Section("Season \(season)") {
                    ForEach(episodes(inSeason: season)) { record in
                        row(for: record)
                    }
                }
            }
        }
        .navigationTitle(showTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(settings.theme.backgroundGradient.ignoresSafeArea())

        // Pop back automatically once the last episode is removed.
        .onChange(of: records.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    private func row(for record: DownloadRecord) -> some View {
        Button {
            onPlay(record)
        } label: {
            HStack(spacing: 12) {
                FadeInImage(url: record.episodeStillURL)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.episodeListLabel)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(record.fileSizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await manager.delete(id: record.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
