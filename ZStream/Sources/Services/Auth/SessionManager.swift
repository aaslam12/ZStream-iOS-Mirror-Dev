//
//  SessionManager.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var session: AuthSession?
    private let tokenKey = "celeste_session_token"
    private let userIdKey = "celeste_user_id"
    private let profileKey = "celeste_account_profile"

    init() { loadFromDisk() }

    var isSignedIn: Bool { session != nil }

    func save(_ session: AuthSession) {
        self.session = session
        KeychainStore.set(session.sessionToken, forKey: tokenKey)
        KeychainStore.set(session.userId, forKey: userIdKey)
        if let data = try? JSONEncoder().encode(session.profile), let string = String(data: data, encoding: .utf8) {
            KeychainStore.set(string, forKey: profileKey)
        }
    }

    func signOut() {
        session = nil
        KeychainStore.delete(forKey: tokenKey)
        KeychainStore.delete(forKey: userIdKey)
        KeychainStore.delete(forKey: profileKey)
    }

    private func loadFromDisk() {
        guard
            let token = KeychainStore.get(forKey: tokenKey),
            let userId = KeychainStore.get(forKey: userIdKey),
            let profileString = KeychainStore.get(forKey: profileKey),
            let profileData = profileString.data(using: .utf8),
            let profile = try? JSONDecoder().decode(AccountProfile.self, from: profileData)
        else { return }
        session = AuthSession(sessionToken: token, userId: userId, profile: profile)
    }
}
