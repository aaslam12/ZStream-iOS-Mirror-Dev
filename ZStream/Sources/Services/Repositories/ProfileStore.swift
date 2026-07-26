//
//  ProfileStore.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import Foundation

/// Reads and write to user profile, not cached backed
actor ProfileStore {
    private let defaults = UserDefaults.standard
    private let key = "user_profile"

    func load() -> UserProfile {
        guard
            let data = defaults.data(forKey: key),
            let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else {
            return UserProfile(displayName: "Guest", avatarURL: nil)
        }
        return profile
    }

    func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}
