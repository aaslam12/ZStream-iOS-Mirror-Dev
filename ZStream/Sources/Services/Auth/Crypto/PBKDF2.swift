//
//  PBKDF2.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import CommonCrypto
import Foundation

enum PBKDF2 {
    static func deriveKey(passwordBytes: Data, salt: String, iterations: Int32 = 2048, keyLength: Int = 32) -> Data {
        var derivedKey = Data(count: keyLength)
        let saltData = Data(salt.utf8)

        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes -> Int32 in
            saltData.withUnsafeBytes { saltBytes -> Int32 in
                passwordBytes.withUnsafeBytes { passwordBytesPtr -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytesPtr.bindMemory(to: Int8.self).baseAddress, passwordBytes.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress, keyLength
                    )
                }
            }
        }
        precondition(result == kCCSuccess, "PBKDF2 derivation failed")
        return derivedKey
    }
}
