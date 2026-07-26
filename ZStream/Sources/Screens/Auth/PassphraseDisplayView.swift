//
//  PassphraseDisplayView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

struct PassphraseDisplayView: View {
    let words: [String]
    let onSaved: () -> Void
    let onUsePasskey: () async -> Void

    @State private var isCreatingPasskey = false
    @State private var passkeyError: String?
    @State private var secondsRemaining = 3
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.circle").font(.system(size: 40)).foregroundStyle(.blue)
                Text("Your passphrase").font(.title2.bold())

                (Text("Your passphrase acts as your username and password. Make sure to keep it safe — you'll need it to log in. ")
                    .foregroundStyle(.secondary)
                 + Text("Do NOT lose your passphrase!").bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    Text("Passphrase").bold().frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(words, id: \.self) { word in
                            Text(word)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Button {
                        UIPasteboard.general.string = words.joined(separator: " ")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                Button("I have saved my passphrase") { onSaved() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)

                Button {
                    Task {
                        isCreatingPasskey = true
                        passkeyError = nil
                        await onUsePasskey()
                        isCreatingPasskey = false
                    }
                } label: {
                    if isCreatingPasskey {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Use passkey instead", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCreatingPasskey)

                if let passkeyError {
                    Text(passkeyError).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .task {
            for _ in 0..<3 {
                try? await Task.sleep(for: .seconds(1))
                secondsRemaining -= 1
            }
        }
    }
}
