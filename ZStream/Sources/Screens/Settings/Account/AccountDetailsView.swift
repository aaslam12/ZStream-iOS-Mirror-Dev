//
//  AccountDetailsView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var path: NavigationPath
    
    let session: AuthSession

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color(hex: session.profile.colorOneHex)).frame(width: 72, height: 72)
                        Image(systemName: session.profile.iconName).font(.system(size: 28)).foregroundStyle(.white)
                    }
                    Text(session.profile.deviceName).font(.title3.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .listRowBackground(Color.clear)

            Section {
                Button("Sign Out", role: .destructive) {
                    sessionManager.signOut()
                    path.removeLast()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Account")
    }
}
