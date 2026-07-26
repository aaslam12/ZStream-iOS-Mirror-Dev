//
//  ExportOptionsSheet.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import SwiftUI
import AVFoundation

struct ExportOptionsSheet: View {
    let record: DownloadRecord
    @Environment(\.dismiss) private var dismiss

    @State private var trackInfo: MediaTrackInfo?
    @State private var selectedFormat: ExportFormat = .mp4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Details") {
                        if let trackInfo {
                            detailRow("Duration", trackInfo.duration)
                            detailRow("Resolution", trackInfo.resolution)
                            detailRow("Video Codec", trackInfo.videoCodec)
                            detailRow("Video Bitrate", trackInfo.videoBitrate)
                            detailRow("Frame Rate", trackInfo.frameRate)
                            detailRow("Audio", trackInfo.audioCodec)
                            detailRow("Channels", trackInfo.audioChannels)
                            detailRow("Language", trackInfo.audioLanguage)
                        } else {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Reading media info…").foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        ForEach(ExportFormat.allCases) { format in
                            Button {
                                selectedFormat = format
                            } label: {
                                HStack {
                                    Text(format.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedFormat == format {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Export As")
                    } footer: {
                        Text("Format conversion is coming in a future update.")
                    }
                }
                .listStyle(.insetGrouped)

                Button {
                    // disabled
                } label: {
                    Text("Export")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle(record.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                trackInfo = await MediaInspector.inspect(url: record.resolvedFileURL)
            }
        }
    }
    
    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value)
            }
        }
    }
}
