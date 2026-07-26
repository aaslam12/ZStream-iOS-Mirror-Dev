//
//  UserProfile.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Model of whatver user data needs to be stored
struct UserProfile: Codable {
    var displayName: String
    var avatarURL: URL?
}
