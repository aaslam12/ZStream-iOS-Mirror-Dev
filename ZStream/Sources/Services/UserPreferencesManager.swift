//
//  UserPreferencesManager.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/18/26.
//

import Foundation

enum UserPreferencesManager {
    enum Key: String {
        case trustedBackendURL
        case imageCacheLevel
    }

    static func mark<T>(_ key: Key, value: T) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func value<T>(for key: Key) -> T? {
        UserDefaults.standard.object(forKey: key.rawValue) as? T
    }

    static func bool(for key: Key, default defaultValue: Bool = false) -> Bool {
        UserDefaults.standard.object(forKey: key.rawValue) == nil
            ? defaultValue
            : UserDefaults.standard.bool(forKey: key.rawValue)
    }

    static func clear(_ key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }
}
