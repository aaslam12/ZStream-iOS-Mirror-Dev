//
//  DownloadedCard.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI

struct DownloadedCard: View {
    let record: DownloadRecord
    let onPlay: () -> Void
    let onDelete: () -> Void
    var onDetails: () -> Void = {}

    @State private var isPresentingExportSheet = false
    @State private var deleteScale: CGFloat = 1
    @State private var deleteOpacity: Double = 1

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    FadeInImage(url: record.posterURL)
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, .green)
                        .padding(6)
                }

                Text(record.title).font(.caption.bold()).lineLimit(1).frame(width: 110, alignment: .leading)
                Text(record.fileSizeFormatted).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(deleteScale)
        .opacity(deleteOpacity)
        .contextMenu {
            Button(action: onDetails) {
                Label("Details", systemImage: "info.circle")
            }

            Button {
                isPresentingExportSheet = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive, action: animateDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isPresentingExportSheet) {
            ExportOptionsSheet(record: record)
        }
    }

    /// A quick "pop then implode" before actually removing the record —
    /// scale up to 1.2x, then collapse to nothing and fade out.
    private func animateDelete() {
        withAnimation(.easeOut(duration: 0.12)) {
            deleteScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.22)) {
                deleteScale = 0.01
                deleteOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onDelete()
            }
        }
    }
}
