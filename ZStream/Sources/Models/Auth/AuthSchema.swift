//
//  AuthSchema.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation

struct MetaResponse: Codable {
    let version: String
    let name: String
    let description: String?
    let hasCaptcha: Bool
    let captchaClientKey: String?
}

struct AuthChallengeResponse: Codable {
    let challenge: String
}

struct BackendProfile: Codable {
    let colorA: String
    let colorB: String
    let icon: String
}

struct UserResponse: Codable {
    let id: String
    let namespace: String
    let nickname: String
    let permissions: [String]
    let profile: BackendProfile
}

struct SessionResponse: Codable {
    let id: String
    let userId: String?
    let createdAt: String
    let accessedAt: String
    let device: String
    let userAgent: String
}

struct RegisterCompleteResponse: Codable {
    let user: UserResponse
    let session: SessionResponse
    let token: String
}

struct LoginCompleteResponse: Codable {
    let session: SessionResponse
    let token: String
}

struct MeResponse: Codable {
    let user: UserResponse
    let session: SessionResponse
}
