//
//  PassphraseConfirmView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

struct PassphraseConfirmView: View {
    let expectedWords: [String]
    let isSubmitting: Bool
    let errorMessage: String?
    let onConfirm: () -> Void
    @State private var input: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.shield").font(.system(size: 40)).foregroundStyle(.blue)
            Text("Confirm your passphrase").font(.title2.bold())
            Text("Type your 12-word passphrase, separated by spaces, to confirm you saved it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                TextField("word1 word2 word3 ...", text: $input, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding()
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                Button {
                    if let clipboardText = UIPasteboard.general.string {
                        input = clipboardText
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            Spacer()
            
            Button {
                onConfirm()
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .disabled(!matches || isSubmitting)
            .buttonStyle(.borderedProminent)

        }
        .padding(.bottom, 24)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = false
        }
        .padding(24)
    }

    private var matches: Bool {
        let cleanedInput = input
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let cleanedExpected = expectedWords.map { $0.lowercased() }
        return cleanedInput == cleanedExpected
    }
}
