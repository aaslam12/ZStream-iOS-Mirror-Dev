//
//  AccountSyncRow.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct AccountSyncRow: View {
    let onSignUp: () -> Void
    let onLogIn: () -> Void
        
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .frame(width: 24)
                    .foregroundStyle(.yellow)
                Text("Sync to Cloud")
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.92, blue: 0.50),
                                Color(red: 0.95, green: 0.74, blue: 0.18),
                                Color(red: 0.80, green: 0.58, blue: 0.10)
                            ],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                Spacer()
            }

            HStack(spacing: 18) {
                Spacer()
                Button("Sign Up") { onSignUp() }
                    .frame(width: 140)
                    .buttonBorderShape(.roundedRectangle(radius: 10))
                    .padding(.vertical, 8)
                    .buttonStyle(.borderedProminent)

                Button("Log In") { onLogIn() }
                    .frame(width: 140)
                    .buttonBorderShape(.roundedRectangle(radius: 10))
                    .padding(.vertical, 8)
                    .buttonStyle(.bordered)
                Spacer()
            }
            .controlSize(.large)

            Text("Create an account to sync bookmarks and watch history across your devices.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }
}
