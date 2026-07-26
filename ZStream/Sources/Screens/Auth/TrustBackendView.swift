//
//  TrustBackendView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

struct TrustBackendView: View {
    let onTrust: () -> Void
    let onClose: () -> Void
    @State private var meta: MetaResponse?
    @State private var isLoadingMeta = true

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack").font(.system(size: 48)).foregroundStyle(.blue)
            Text("Do you trust this backend?").font(.title2.bold())
            
            (
                Text("Z-Stream is Open Source, anyone can point the app at a different backend. Only continue if you trust the server below. ")
                    .foregroundStyle(.secondary)
                +
                Text("The server will be able to see your account data.")
                    .bold()
                    .foregroundStyle(.secondary)
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            
            VStack(spacing: 6) {
                Text(DefaultEndpoints.base)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
                
                if isLoadingMeta {
                    ProgressView().padding(.top, 4)
                } else if let meta {
                    HStack(spacing: 4) {
                        Text(meta.name)
                            .foregroundStyle(.secondary)
                        
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .shadow(color: .green.opacity(0.8), radius: 4)
                        
                        Text("Connected")
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                } else {
                    Text("Couldn't reach this backend")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
                        
            Button("I trust this backend", role: .destructive) { onTrust() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isLoadingMeta)
        }
        .padding(24)
        .task {
            meta = try? await DefaultAuthRepository().fetchMeta()
            isLoadingMeta = false
        }
    }
}
