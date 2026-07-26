//
//  ProfileView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    @StateObject private var signup = SignupCoordinator()
    @State private var isPresentingLogin = false
    
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack(path: $signup.path) {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                
                Section {
                    if sessionManager.session != nil {
                        NavigationLink(value: MenuDestination.account) {
                            MenuRow(icon: "person.crop.circle.fill", title: "Account")
                        }
                    } else {
                        AccountSyncRow(
                            onSignUp: { signup.start() },
                            onLogIn: { isPresentingLogin = true }
                        )
                    }
                    
                    NavigationLink(value: MenuDestination.settings) {
                        MenuRow(icon: "gearshape.fill", title: "Settings")
                    }
                    NavigationLink(value: MenuDestination.watchHistory) {
                        MenuRow(icon: "clock.fill", title: "Watch History")
                    }
                    MenuRow(icon: "wand.and.stars", title: "My Algorithm", badge: "Coming Soon", isDisabled: true)
                    NavigationLink(value: MenuDestination.aboutFAQ) {
                        MenuRow(icon: "questionmark.circle.fill", title: "About and FAQ")
                    }
                }
                
                Section {
                    socialRow
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ThemeBackground(theme: settings.theme))
            .navigationTitle("Profile")
            .navigationDestination(for: MenuDestination.self) { destination in
                switch destination {
                case .settings: SettingsView()
                case .watchHistory: WatchHistoryView()
                case .aboutFAQ: AboutFAQView()
                case .account:
                    if let session = sessionManager.session {
                        AccountDetailView(path: $signup.path, session: session)
                    }
                }
            }
            .navigationDestination(for: SignupStep.self) { step in
                destination(for: step)
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab != .profile {
                signup.path = NavigationPath()
            }
        }
        .sheet(isPresented: $signup.isPresentingTrustSheet) {
            TrustBackendView(
                onTrust: { signup.trusted() },
                onClose: { signup.isPresentingTrustSheet = false }
            )
            .presentationDetents([.height(500)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isPresentingLogin) {
            LoginView()
        }
    }
    
    private var header: some View {
        VStack(spacing: 10) {
            if let session = sessionManager.session {
                ZStack {
                    Circle().fill(Color(hex: session.profile.colorOneHex)).frame(width: 72, height: 72)
                    Image(systemName: session.profile.iconName).font(.system(size: 28)).foregroundStyle(.white)
                }
                Text(session.profile.deviceName)
                    .font(.title2.bold())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    private var socialRow: some View {
        HStack(spacing: 20) {
            Spacer()
            Link(destination: URL(string: "https://discord.gg/your-invite")!) {
                socialIcon("bubble.left.and.bubble.right.fill")
            }
            Link(destination: URL(string: "https://your-support-url.example.com")!) {
                socialIcon("questionmark.bubble.fill")
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private func socialIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
            .frame(width: 52, height: 52)
            .background(.white.opacity(0.06), in: Circle())
    }
    
    @ViewBuilder
    private func destination(for step: SignupStep) -> some View {
        switch step {
        case .passphraseDisplay:
            PassphraseDisplayView(
                words: signup.generatedPassphrase,
                onSaved: {
                    signup.authMethod = .passphrase
                    signup.path.append(SignupStep.accountInfo)
                },
                onUsePasskey: {
                    await createPasskey()
                }
            )
        case .accountInfo:
            AccountInfoView(profile: $signup.profile) {
                switch signup.authMethod {
                case .passphrase:
                    signup.path.append(SignupStep.passphraseConfirm)
                case .passkey:
                    Task { await createAccount() }
                }
            }
        case .passphraseConfirm:
            PassphraseConfirmView(
                expectedWords: signup.generatedPassphrase,
                isSubmitting: isCreating,
                errorMessage: errorMessage,
                onConfirm: {
                    Task { await createAccount() }
                }
            )
        case .trustBackend:
            EmptyView()
        }
    }
    
    private func createPasskey() async {
        do {
            var challenge = Data(count: 32)
            _ = challenge.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            var userID = Data(count: 16)
            _ = userID.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            
            let credential = try await PasskeyManager().register(
                username: UIDevice.current.name,
                challenge: challenge,
                userID: userID
            )
            signup.authMethod = .passkey(credentialID: credential.credentialID)
            signup.path.append(SignupStep.accountInfo)
        } catch {
            print("Passkey registration failed: \(error)")
            // surface this in PassphraseDisplayView via a passed-in errorMessage to make it visible
        }
    }
    
    private func createAccount() async {
        isCreating = true
        errorMessage = nil
        do {
            let passwordBytes: Data
            switch signup.authMethod {
            case .passphrase:
                passwordBytes = Data(signup.generatedPassphrase.joined(separator: " ").utf8)
            case .passkey(let credentialID):
                passwordBytes = credentialID
            }
            
            let (_, session) = try await AuthBackend.current.register(
                passwordBytes: passwordBytes,
                deviceName: signup.profile.deviceName,
                profile: signup.profile,
                captchaToken: nil
            )
            sessionManager.save(session)
            signup.reset()
        } catch {
            print("Registration failed: \(error)")
            errorMessage = "Something went wrong creating your account. Please try again."
        }
        isCreating = false
    }
}

private enum MenuDestination: Hashable {
    case settings
    case watchHistory
    case aboutFAQ
    case account
}
