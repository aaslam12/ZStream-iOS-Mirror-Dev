//
//  StorageBar.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import SwiftUI

struct StorageBar: View {
    let usedBytes: Int64
    let freeBytes: Int64
    var accent: Color = .accentColor
    let onInfoTap: () -> Void

    @State private var animatedProgress: Double = 0

    private var usedFraction: Double {
        let total = usedBytes + freeBytes
        guard total > 0 else { return 0 }
        return Double(usedBytes) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
                .font(.caption2.bold())
                .foregroundStyle(accent)
                .fixedSize()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * animatedProgress)
                }
            }
            .frame(height: 8)

            Text(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()

            Button(action: onInfoTap) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = usedFraction
            }
        }
    }
}
