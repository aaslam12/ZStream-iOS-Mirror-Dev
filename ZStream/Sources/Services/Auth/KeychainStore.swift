//
//  KeychainStore.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import Foundation
import Security

/// Session tokens and anything passphrase-derived belong in Keychain, not
/// UserDefaults — it's the only iOS store that's encrypted at rest and
/// excluded from unencrypted backups by default.
enum KeychainStore {
    static func set(_ value: String, forKey key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(newItem as CFDictionary, nil)
    }

    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
