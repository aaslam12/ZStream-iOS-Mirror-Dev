//
//  AuthCrypto.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import CryptoKit
import Foundation

enum AuthCryptoError: Error {
    case invalidSeed
}

/// Mirrors the backend's crypto.ts exactly: PBKDF2(SHA-256, salt: "mnemonic",
/// 2048 iterations, 32-byte output) → seed → Ed25519 keypair → sign challenge → base64url.
enum AuthCrypto {
    /// `passwordBytes` is either the space-joined mnemonic (as UTF-8) or a
    /// passkey's raw credential ID — the backend treats both the same way.
    static func deriveSeed(passwordBytes: Data) -> Data {
        PBKDF2.deriveKey(passwordBytes: passwordBytes, salt: "mnemonic", iterations: 2048, keyLength: 32)
    }

    static func keyPair(fromSeed seed: Data) throws -> Curve25519.Signing.PrivateKey {
        guard seed.count == 32 else { throw AuthCryptoError.invalidSeed }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    static func sign(challengeCode: String, with privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let signature = try privateKey.signature(for: Data(challengeCode.utf8))
        return base64URLEncode(signature)
    }

    static func publicKeyString(for privateKey: Curve25519.Signing.PrivateKey) -> String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
