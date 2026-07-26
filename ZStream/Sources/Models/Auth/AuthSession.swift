//
//  AuthSession.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

struct AuthSession: Codable {
    let sessionToken: String
    let userId: String
    let profile: AccountProfile
}
