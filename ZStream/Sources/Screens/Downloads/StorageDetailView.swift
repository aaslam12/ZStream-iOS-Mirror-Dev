//
//  StorageDetailView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import SwiftUI
import Charts

struct StorageDetailView: View {
    let records: [DownloadRecord]
    /// In-flight downloads — used to show a "reserved" chunk for whatever's
    /// currently downloading, sized from AVFoundation's own running estimate
    /// of the final asset size, instead of that space being invisible until
    /// the download finishes.
    var activeDownloads: [ActiveDownload] = []
    let onDelete: (String) -> Void

    @State private var animateChart = false
    @State private var isPresentingDeleteAllConfirm = false

    private let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .yellow]
    private let freeSpaceColor = Color.gray.opacity(0.35)
    private let freeSpaceMaxDegrees: Double = 75

    private var totalDownloadedBytes: Int64 {
        records.reduce(0) { $0 + $1.fileSizeBytes }
    }

    /// Active downloads whose final size AVFoundation has actually estimated
    /// yet — `bytesExpected` starts at 0 until enough of the playlist has
    /// been read, so those are skipped rather than shown as a zero-size chunk.
    private var pendingDownloads: [ActiveDownload] {
        activeDownloads.filter { $0.bytesExpected > 0 }
    }

    private var pendingBytes: Int64 {
        pendingDownloads.reduce(0) { $0 + $1.bytesExpected }
    }

    private var deviceFreeBytes: Int64 {
        DownloadStorage.deviceCapacity().free
    }

    /// One entry per visual slice, in draw order. Free Space is always last,
    /// which is what places it right before 12 o'clock (SectorMark draws
    /// clockwise starting at 12, so the final slice closes the circle there).
    private struct Slice: Identifiable {
        let id: String
        let label: String
        let degrees: Double
        let color: Color
        let record: DownloadRecord?
        var isPending: Bool = false
    }

    private var slices: [Slice] {
        let usedBytes = Double(totalDownloadedBytes)
        let pendingBytesD = Double(pendingBytes)
        let freeBytes = Double(deviceFreeBytes)
        let combinedTotal = usedBytes + pendingBytesD + freeBytes

        guard usedBytes > 0 || pendingBytesD > 0 else {
            return [Slice(id: "free-space", label: "Free Space", degrees: 360, color: freeSpaceColor, record: nil)]
        }

        let trueFreeDegrees = combinedTotal > 0 ? (freeBytes / combinedTotal) * 360 : 0
        let cappedFreeDegrees = min(trueFreeDegrees, freeSpaceMaxDegrees)
        let remainingDegrees = 360 - cappedFreeDegrees
        let occupiedBytes = usedBytes + pendingBytesD

        var result: [Slice] = []

        for (index, record) in records.enumerated() {
            let share = Double(record.fileSizeBytes) / occupiedBytes
            result.append(Slice(
                id: record.id,
                label: record.title,
                degrees: share * remainingDegrees,
                color: colors[index % colors.count],
                record: record
            ))
        }

        for (index, download) in pendingDownloads.enumerated() {
            let share = Double(download.bytesExpected) / occupiedBytes
            result.append(Slice(
                id: download.id,
                label: download.title,
                degrees: share * remainingDegrees,
                color: colors[(records.count + index) % colors.count],
                record: nil,
                isPending: true
            ))
        }

        result.append(Slice(id: "free-space", label: "Free Space", degrees: cappedFreeDegrees, color: freeSpaceColor, record: nil))

        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    chart
                        .frame(height: 240)
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                }
                
                Section {
                    HStack(spacing: 12) {
                        Circle().fill(freeSpaceColor).frame(width: 10, height: 10)
                        Text("Free Space")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: deviceFreeBytes, countStyle: .file))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(colors[index % colors.count])
                                .frame(width: 10, height: 10)
                            Text(record.title).lineLimit(1)
                            Spacer()
                            Text(record.fileSizeFormatted)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                onDelete(record.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text(usedByZStreamText)
                }

                if !pendingDownloads.isEmpty {
                    Section {
                        ForEach(Array(pendingDownloads.enumerated()), id: \.element.id) { index, download in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(colors[(records.count + index) % colors.count])
                                    .opacity(0.55)
                                    .frame(width: 10, height: 10)
                                Text(download.title).lineLimit(1)
                                Spacer()
                                Text("~\(ByteCountFormatter.string(fromByteCount: download.bytesExpected, countStyle: .file))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text("Downloading")
                    } footer: {
                        Text("Estimated final size — reserved now so the total makes sense before the download finishes.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            
            if !records.isEmpty {
                deleteAllButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(.clear)
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            animateChart = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.9)) {
                    animateChart = true
                }
            }
        }
        .alert("Delete all downloads?", isPresented: $isPresentingDeleteAllConfirm) {
            Button("Delete All", role: .destructive) {
                for record in records { onDelete(record.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all downloaded videos from your device. This can't be undone.")
        }
    }
    
    private var usedByZStreamText: String {
        guard totalDownloadedBytes > 0 else {
            return "No space used by Z-Stream"
        }
        return "Used by Z-Stream: \(ByteCountFormatter.string(fromByteCount: totalDownloadedBytes, countStyle: .file))"
    }
    
    @ViewBuilder
    private var deleteAllButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .destructive) {
                isPresentingDeleteAllConfirm = true
            } label: {
                Text("Delete All Downloads")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
        } else {
            Button(role: .destructive) {
                isPresentingDeleteAllConfirm = true
            } label: {
                Text("Delete All Downloads")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
    
    private var chart: some View {
        Chart {
            ForEach(slices) { slice in
                SectorMark(
                    angle: .value("Degrees", animateChart ? slice.degrees : 0),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(slice.color)
                .opacity(slice.isPending ? 0.55 : 1)
                .cornerRadius(4)
            }
        }
        .chartLegend(.hidden)
        .animation(.easeInOut(duration: 0.6), value: totalDownloadedBytes)
        .animation(.easeInOut(duration: 0.6), value: pendingBytes)
        .overlay {
            VStack(spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: totalDownloadedBytes + pendingBytes, countStyle: .file))
                    .font(.title3.bold())
                Text(pendingBytes > 0 ? "Used + Downloading" : "Used by Z-Stream")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
