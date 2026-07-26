//
//  DefaultAuthRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

enum AuthError: Error {
    case missingUser
    case invalidChallenge
}

struct DefaultAuthRepository: AuthProtocol {
    func fetchMeta() async throws -> MetaResponse {
        try await fetchJSON(MetaResponse.self, from: DefaultEndpoints.meta(), auth: .none)
    }

    /// `passwordBytes`: mnemonic joined with spaces, UTF-8 encoded — or a
    /// passkey credential ID's raw bytes, for the passkey path.
    func register(passwordBytes: Data, deviceName: String, profile: AccountProfile, captchaToken: String?) async throws -> (user: UserResponse, session: AuthSession) {
        let seed = AuthCrypto.deriveSeed(passwordBytes: passwordBytes)
        let keyPair = try AuthCrypto.keyPair(fromSeed: seed)
        let publicKey = AuthCrypto.publicKeyString(for: keyPair)

        struct StartBody: Encodable { let captchaToken: String? }
        let start = try await postJSON(AuthChallengeResponse.self, to: DefaultEndpoints.registerStart(), body: StartBody(captchaToken: captchaToken), auth: .none)

        let signature = try AuthCrypto.sign(challengeCode: start.challenge, with: keyPair)

        struct ChallengePayload: Encodable { let code: String; let signature: String }
        struct CompleteBody: Encodable {
            let namespace = "movie-web"
            let publicKey: String
            let challenge: ChallengePayload
            let device: String
            let profile: BackendProfile
        }

        let result = try await postJSON(
            RegisterCompleteResponse.self,
            to: DefaultEndpoints.registerComplete(),
            body: CompleteBody(
                publicKey: publicKey,
                challenge: ChallengePayload(code: start.challenge, signature: signature),
                device: deviceName,
                profile: BackendProfile(colorA: profile.colorOneHex, colorB: profile.colorTwoHex, icon: profile.iconName)
            ),
            auth: .none
        )

        KeychainStore.set(seed.base64EncodedString(), forKey: "celeste_seed")

        let session = AuthSession(sessionToken: result.token, userId: result.user.id, profile: profile)
        return (result.user, session)
    }

    func login(passwordBytes: Data, deviceName: String) async throws -> AuthSession {
        let seed = AuthCrypto.deriveSeed(passwordBytes: passwordBytes)
        let keyPair = try AuthCrypto.keyPair(fromSeed: seed)
        let publicKey = AuthCrypto.publicKeyString(for: keyPair)

        struct StartBody: Encodable { let publicKey: String }
        let start = try await postJSON(AuthChallengeResponse.self, to: DefaultEndpoints.loginStart(), body: StartBody(publicKey: publicKey), auth: .none)

        let signature = try AuthCrypto.sign(challengeCode: start.challenge, with: keyPair)

        struct ChallengePayload: Encodable { let code: String; let signature: String }
        struct CompleteBody: Encodable {
            let namespace = "movie-web"
            let publicKey: String
            let challenge: ChallengePayload
            let device: String
        }

        let result = try await postJSON(
            LoginCompleteResponse.self,
            to: DefaultEndpoints.loginComplete(),
            body: CompleteBody(publicKey: publicKey, challenge: ChallengePayload(code: start.challenge, signature: signature), device: deviceName),
            auth: .none
        )

        // login/complete doesn't return the profile — fetch it separately.
        let me = try await fetchJSON(MeResponse.self, from: DefaultEndpoints.me(), auth: .bearer(result.token))

        KeychainStore.set(seed.base64EncodedString(), forKey: "celeste_seed")

        let profile = AccountProfile(
            deviceName: deviceName,
            iconName: me.user.profile.icon,
            colorOneHex: me.user.profile.colorA,
            colorTwoHex: me.user.profile.colorB
        )
        
        return AuthSession(sessionToken: result.token, userId: me.user.id, profile: profile)
    }
}
