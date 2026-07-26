//
//  SourceResolutionOverlay.swift
//  ZStream
//
//  Full-screen loading state shown while SourceResolver works through
//  AvailableSources.all
//

import SwiftUI
import ZStreamCore

struct SourceResolutionOverlay: View {
    let sources: [SourceResult]
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)

                VStack(spacing: 6) {
                    ForEach(sources, id: \.id) { source in
                        SourceStatusRow(source: source)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
        }
    }
}

private struct SourceStatusRow: View {
    let source: SourceResult

    private var color: Color {
        switch source.status {
        case .idle: return .white.opacity(0.5)
        case .trying: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch source.status {
                case .trying:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(color)
                        .scaleEffect(0.5)
                case .success:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                case .failed:
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                case .idle:
                    Color.clear
                }
            }
            .frame(width: 12, height: 12)

            Text(Self.displayName(for: source))
                .font(.system(size: 12))
                .foregroundStyle(color)
        }
        .padding(.vertical, 3)
    }

    private static func displayName(for source: SourceResult) -> String {
        let base = SourceDisplayName.forID(source.id)

        let codecLabel: String
        switch source.codec.lowercased() {
        case "hevc", "h265": codecLabel = "HEVC"
        case "h264", "avc": codecLabel = "H.264"
        default: codecLabel = ""
        }

        return codecLabel.isEmpty ? base : "\(base) • \(codecLabel)"
    }
}
