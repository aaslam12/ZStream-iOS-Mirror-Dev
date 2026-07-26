//
//  DownloadingRow.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI

struct DownloadingRow: View {
    let item: ActiveDownload
    let onCancel: () -> Void
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            FadeInImage(url: item.posterURL)
                .frame(width: 54, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.subheadline.bold()).lineLimit(1)
                statusView
            }

            Spacer()

            if isPausable {
                Button(action: isPaused ? onResume : onPause) {
                    Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // A failed row is really a notification, not an active transfer —
            // there's nothing left to cancel, so acknowledge it with "OK"
            // instead of showing an (x) that implies cancelling something live.
            if isFailed {
                Button(action: onCancel) {
                    Text("OK")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var isFailed: Bool {
        if case .failed = item.status { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = item.status { return true }
        return false
    }

    /// Only a task that's actually transferring (or was) can be suspended —
    /// nothing to pause while still queued or after it's failed.
    private var isPausable: Bool {
        switch item.status {
        case .downloading, .paused: return true
        case .queued, .failed: return false
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .queued:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .downloading(let progress):
            ProgressView(value: progress)
                .tint(.blue)
            byteSizeLabel(progress: progress)
        case .paused(let progress):
            ProgressView(value: progress)
                .tint(.gray)
            HStack(spacing: 4) {
                Text("Paused").font(.caption2).foregroundStyle(.secondary)
                Text("• \(Int(progress * 100))%").font(.caption2).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).font(.caption2).foregroundStyle(.red)
        }
    }

    /// "120 MB / 850 MB (14%)" when we have a byte estimate yet, else just
    /// the percentage — `bytesExpected` starts at 0 until AVFoundation has
    /// read enough of the playlist to estimate a total size.
    private func byteSizeLabel(progress: Double) -> some View {
        Group {
            if item.bytesExpected > 0 {
                Text("\(formattedBytes(item.bytesReceived)) / \(formattedBytes(item.bytesExpected)) (\(Int(progress * 100))%)")
            } else {
                Text("\(Int(progress * 100))%")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
