//
//  SignupCoordinator.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

enum SignupAuthMethod {
    case passphrase
    case passkey(credentialID: Data)
}

@MainActor
final class SignupCoordinator: ObservableObject {
    @Published var isPresentingTrustSheet = false
    @Published var path = NavigationPath()

    @Published var generatedPassphrase: [String] = []
    @Published var authMethod: SignupAuthMethod = .passphrase
    @Published var profile = AccountProfile(deviceName: "", iconName: ProfileIconOption.icons[0], colorOneHex: ProfileIconOption.colors[0], colorTwoHex: ProfileIconOption.colors[0])

    func start() {
        if UserPreferencesManager.value(for: .trustedBackendURL) == DefaultEndpoints.base {
            generatedPassphrase = PassphraseGenerator.generate()
            path.append(SignupStep.passphraseDisplay)
        } else {
            isPresentingTrustSheet = true
        }
    }

    func trusted() {
        UserPreferencesManager.mark(.trustedBackendURL, value: DefaultEndpoints.base)
        isPresentingTrustSheet = false
        generatedPassphrase = PassphraseGenerator.generate()
        path.append(SignupStep.passphraseDisplay)
    }

    func reset() {
        path = NavigationPath()
        generatedPassphrase = []
        authMethod = .passphrase
        profile = AccountProfile(deviceName: "", iconName: ProfileIconOption.icons[0], colorOneHex: ProfileIconOption.colors[0], colorTwoHex: ProfileIconOption.colors[0])
    }
}
