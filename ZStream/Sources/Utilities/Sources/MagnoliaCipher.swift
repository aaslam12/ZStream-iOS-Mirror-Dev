//
//  MagnoliaCipher.swift
//  ZStream
//
//  Decrypts Magnolia's encrypted provider responses. Base64url payload,
//  then a bespoke keystream cipher seeded from the response `seed` and the
//  TMDB media ID — pure integer arithmetic, no real cryptographic primitive
//  involved, so this needs no crypto library at all.
//

import Foundation

enum MagnoliaCipher {

    /// Decrypts a base64url-encoded, keystream-ciphered payload. Returns
    /// nil if the payload is malformed or fails the magic-header check.
    static func decrypt(payload: String, seed: String, mediaId: UInt32) -> Data? {
        guard var bytes = decodeBase64URL(payload), bytes.count >= 4 else { return nil }

        var fnv: UInt32 = 2166136261
        for byte in seed.utf8 {
            fnv = (fnv ^ UInt32(byte)) &* 16777619
        }

        var a = murmurMix(murmurMix(fnv) ^ murmurMix(mediaId ^ 2654435769))

        var state = [UInt32](repeating: 0, count: 61)
        var present = [Bool](repeating: false, count: 61)
        for i: UInt32 in 0..<8 {
            let t = Int(a % 61)
            a = rotl(a &+ 2654435769, 7 &+ (7 & i))
            state[t] = a ^ murmurMix(a)
            present[t] = true
            a = murmurMix(a &+ UInt32(t))
        }

        var acc = murmurMix(2779096485 ^ a)
        var counter: UInt32 = 0
        var word: UInt32 = 0

        for i in 0..<bytes.count {
            if i & 3 == 0 {
                let n = Int(acc % 61)
                let d = state[n]
                counter &+= 1
                let inner = d ^ (2654435769 &* counter)
                var v = acc ^ inner
                if present[n] { v |= acc & inner }
                word = rotl(v &+ acc, UInt32(n)) ^ rotl(acc, UInt32(n) &* 7)
                acc = murmurMix(word &+ 2654435769)
                state[n] = acc
                present[n] = true
            }
            bytes[i] ^= UInt8((acc >> (UInt32(i & 3) * 8)) & 0xff)
        }

        // "mvm1" magic header
        guard bytes[0] == 0x6d, bytes[1] == 0x76, bytes[2] == 0x6d, bytes[3] == 0x31 else {
            return nil
        }

        return bytes.subdata(in: 4..<bytes.count)
    }

    private static func murmurMix(_ x: UInt32) -> UInt32 {
        var x = x
        x ^= x >> 16
        x = x &* 2246822507
        x ^= x >> 13
        x = x &* 3266489909
        x ^= x >> 16
        return x
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        let n = n & 31
        guard n != 0 else { return x }
        return (x << n) | (x >> (32 - n))
    }

    private static func decodeBase64URL(_ s: String) -> Data? {
        var base64 = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }
}
