//
//  LoginView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var input: String = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "person.crop.circle").font(.system(size: 40)).foregroundStyle(.blue)
                Text("Log in").font(.title2.bold())
                Text("Enter your 12-word passphrase, separated by spaces.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("word1 word2 word3 ...", text: $input, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task { await loginWithPasskey() }
                } label: {
                    Label("Log in with passkey", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.bottom, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var words: [String] {
        input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
    }

    private func loginWithPasskey() async {
        do {
            var challenge = Data(count: 32)
            _ = challenge.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }

            let credential = try await PasskeyManager().authenticate(challenge: challenge)
            let session = try await AuthBackend.current.login(
                passwordBytes: credential.credentialID,
                deviceName: UIDevice.current.name
            )
            sessionManager.save(session)
            dismiss()
        } catch {
            print("Passkey login failed: \(error)")
            errorMessage = "Passkey login failed."
        }
    }
    
    private func login() async {
        isLoggingIn = true
        errorMessage = nil
        do {
            let passwordBytes = Data(words.joined(separator: " ").utf8)
            let deviceName = UIDevice.current.name
            let session = try await AuthBackend.current.login(passwordBytes: passwordBytes, deviceName: deviceName)
            sessionManager.save(session)
            dismiss()
        } catch {
            errorMessage = "Login failed. Check your passphrase and try again."
        }
        isLoggingIn = false
    }
}
