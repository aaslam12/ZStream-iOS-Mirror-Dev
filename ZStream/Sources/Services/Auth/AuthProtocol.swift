//
//  AuthProtocol.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

/// What the app needs from any auth backend. Anyone forking this project
/// can implement this protocol against a different backend and swap it
/// in via AuthBackend.current — no changes needed anywhere else in the app.
protocol AuthProtocol {
    func fetchMeta() async throws -> MetaResponse
    func register(passwordBytes: Data, deviceName: String, profile: AccountProfile, captchaToken: String?) async throws -> (user: UserResponse, session: AuthSession)
    func login(passwordBytes: Data, deviceName: String) async throws -> AuthSession
}
