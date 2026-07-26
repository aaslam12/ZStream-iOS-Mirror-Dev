//
//  SettingsView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var diskUsageBytes: Int64 = 0

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Language")
                    Spacer()
                    Text("English")
                        .foregroundStyle(.secondary)
                }
                .opacity(0.5)
            } header: {
                Text("Content")
            } footer: {
                HStack(spacing: 4) {
                    Text("Language selection is")
                    Text("coming soon").bold()
                    Text("in a future update.")
                }
            }

            Section("Appearance") {
                NavigationLink {
                    ThemesView()
                } label: {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Text(settings.theme.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Kid Mode", isOn: $settings.kidMode)
            } footer: {
                Text("When on, adult content is excluded from search results and catalogs.")
            }
            
            Section {
                NavigationLink {
                    SourceOrderView()
                } label: {
                    Text("Source Order")
                }

                Toggle("Manually Select the Source", isOn: $settings.manualSourceSelection)
                Toggle("Prioritize Last Used Source", isOn: $settings.prioritizeLastUsedSource)
            } header: {
                Text("Source")
            } footer: {
                Text("Source Order sets which source is tried first when loading a title. Manual selection asks you to pick every time instead. Prioritizing the last used source overrides the order with whatever worked last time for that title.")
            }

            Section {
                Picker("Image Cache Size", selection: Binding(
                    get: { ImageCacheManager.shared.level },
                    set: { ImageCacheManager.shared.level = $0 }
                )) {
                    ForEach(ImageCacheManager.CacheLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)

                HStack {
                    Text("Disk Usage")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: diskUsageBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }

                Button("Clear Image Cache", role: .destructive) {
                    ImageCacheManager.shared.clearAll()
                    diskUsageBytes = 0
                }
            } header: {
                Text("Image Cache")
            } footer: {
                Text("Higher settings keep more images ready instantly, using more storage and memory.")
            }
            .task {
                diskUsageBytes = await ImageCacheManager.shared.currentDiskUsageBytes()
            }
            
            Section {
                NavigationLink {
                    LogViewerView()
                } label: {
                    Text("View Logs")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Captures print output plus system warnings and errors to a file, so issues in Release builds can still be inspected. Keeps the last ~2MB.")
            }

            Button("Send Test Notification (10s)") {
                Task {
                    let granted = await NotificationManager.shared.requestAuthorizationIfNeeded()
                    guard granted else { return }
                    NotificationManager.shared.scheduleTest(
                        id: "test-\(UUID().uuidString)",
                        title: "Test Notification",
                        body: "Scheduling works!",
                        secondsFromNow: 10
                    )
                }
            }
            
            Button("Cancel all pending") {
                Task {
                     NotificationManager.shared.cancelAll()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ThemeBackground(theme: settings.theme))
        .navigationTitle("Settings")
    }
}

// MARK: - Log viewer

/// Shows the tail of `AppLogger`'s captured file (the whole thing can be a
/// couple MB, too much to comfortably render as one Text view) plus a share
/// sheet for pulling the complete file off-device.
struct LogViewerView: View {
    @State private var logText = "Loading…"

    var body: some View {
        ScrollView {
            Text(logText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .background(Color.black)
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: DiagnosticsLog.shared.exportText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    DiagnosticsLog.shared.clear()
                    load()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task { load() }
    }

    private func load() {
        let text = DiagnosticsLog.shared.exportText
        logText = text.isEmpty ? "No logs yet." : text
    }
}

// MARK: - Source order

/// Drag-to-reorder list of every registered source, seeded from the saved
/// order (normalized against the current catalog so stale/new ids never
/// leave gaps or get dropped silently). Always in edit mode since reordering
/// is this screen's only purpose.
struct SourceOrderView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var orderedIds: [String] = []

    private var displayNames: [String: String] {
        Dictionary(uniqueKeysWithValues: AvailableSources.allCandidates().map { ($0.info.id, $0.info.displayName) })
    }

    var body: some View {
        List {
            Section {
                ForEach(orderedIds, id: \.self) { id in
                    Text(displayNames[id] ?? id)
                }
                .onMove(perform: move)
            } footer: {
                Text("Sources are tried in this order when loading a title.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(settings.theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Source Order")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            orderedIds = AvailableSources.normalizedOrder(settings.sourceOrder)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedIds.move(fromOffsets: source, toOffset: destination)
        settings.sourceOrder = orderedIds
    }
}

// MARK: - Theme picker

/// A 2-column grid of theme previews; the active theme is highlighted with a
/// thick accent border. Tapping a card applies it immediately (and persists).
struct ThemesView: View {
    @EnvironmentObject var settings: AppSettings

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(ThemeCatalog.all) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: theme.id == settings.themeID
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.themeID = theme.id
                        }
                    }
                }
            }
            .padding()
        }
        .background(settings.theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                ThemeBackground(theme: theme, blurRadius: 26)
                    .frame(height: 120)

                // A mock "poster" and accent chip to preview the palette.
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.14))
                        .frame(width: 34, height: 50)
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 46, height: 16)
                }
                .padding(12)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? theme.accent : Color.white.opacity(0.12),
                                  lineWidth: isSelected ? 4 : 1)
            )

            HStack(spacing: 6) {
                Text(theme.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }
}
