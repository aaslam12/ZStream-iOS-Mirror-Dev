# iOS Native C++ Integration Guide

## Status
✅ All 11 C++ source files ported from the Android plugin
✅ All JNI/Android code removed
✅ Objective-C++ bridging layer created
✅ Swift-compatible interface ready
✅ `project.yml` wired to a BoringSSL.xcframework dependency
✅ CI builds BoringSSL from source automatically (`.github/workflows/build-ipa.yml`)

The native C++/Obj-C++ sources live under `ZStream/Sources/Native/` and are
compiled directly into the single `ZStream` app target — there's no separate
framework target. `project.yml`'s `ZStream` target already has:
- `SWIFT_OBJC_BRIDGING_HEADER` pointing at `ZStream-Bridging-Header.h`
- `HEADER_SEARCH_PATHS` including `ZStream/Sources/Native/cpp`
- C++17 / exceptions / RTTI enabled
- A `dependencies:` entry linking `ThirdParty/BoringSSL.xcframework`

## Crypto library: BoringSSL, built from source

Same approach as Android: BoringSSL is built from source, pinned to the exact
commit the Android plugin uses (`a945a3ea4cdf8cd683a9d3ad3a66bd3f04a514e6`,
see `zstream-plugin/plugin/src/main/cpp/CMakeLists.txt` in the Android repo),
so crypto/TLS behavior stays identical across platforms. No CocoaPods, no
prebuilt binary committed to the repo.

- **`scripts/build-boringssl.sh`** clones the pinned commit, builds static
  libs for iOS device (arm64) and simulator (arm64 + x86_64 fat), and packages
  them plus headers into `ThirdParty/BoringSSL.xcframework`. macOS + Xcode
  command-line tools only; also needs `cmake`, `ninja`, `go`, `perl` on PATH.
- **`scripts/ios.toolchain.cmake`** is the minimal CMake toolchain file the
  script uses to cross-compile for each iOS platform slice.
- Both `ThirdParty/` and `third_party/` (the script's scratch/build dirs) are
  gitignored — this is built, not committed.

### Local dev (macOS)
```bash
./scripts/build-boringssl.sh   # produces ThirdParty/BoringSSL.xcframework
xcodegen generate
open ZStream.xcodeproj
```
Re-run the script whenever the pinned commit changes; it's a no-op otherwise.

### CI
`.github/workflows/build-ipa.yml` runs on `macos-latest`, caches the
BoringSSL build (keyed on `scripts/build-boringssl.sh`'s contents so a commit
bump invalidates the cache), runs the script, generates the Xcode project,
and archives the app. **Note:** exporting a signed `.ipa` still needs an
`ExportOptions.plist` and a signing identity/provisioning profile wired up as
CI secrets — not set up yet. The workflow currently verifies the app builds
and produces an `.xcarchive` artifact.

## File Organization

| File | Purpose | Depends On |
|------|---------|-----------|
| `crypto_impl.h/cpp` | SHA-256, HMAC, AES-GCM, RAND | BoringSSL |
| `net_common.h/cpp` | HTTPS requests, redirects | BoringSSL (SSL_*) |
| `aspera.cpp`, `aphrodite.cpp`, `cosmic.cpp`, `stellar.cpp`, `fontaine.cpp`, `magnolia.cpp`, `nesterov.cpp`, `shibuya.cpp`, `tokyo.cpp` | Source resolvers | `net_common.h`, `crypto_impl.h` |
| `ZStreamNative.h` | Obj-C interface | `ZStream/Sources/Native/cpp/*` |
| `ZStreamNative.mm` | Obj-C++ bridge | `ZStreamNative.h` |
| `ZStream-Bridging-Header.h` | Swift bridge | `ZStreamNative.h` |

## Swift usage

```swift
import Foundation

class StreamResolver {
    func resolveAspera(tmdb: String, type: String, season: String, episode: String) -> String {
        return ZStreamNative.asperaResolve(tmdb, type: type, season: season, episode: episode)
    }

    func resolveFontaine(tmdb: String, shelf: String, slot: String, type: String) -> String {
        return ZStreamNative.nativeResolve(tmdb, shelf: shelf, slot: slot, type: type)
    }
}
```

## Testing

### Unit tests
```swift
import XCTest

class CryptoTests: XCTestCase {
    func testSHA256() {
        let data = "hello".data(using: .utf8)!
        let digest = ZStreamNative.sha256(data)
        XCTAssertEqual(digest.count, 32)
    }

    func testAESGCM() {
        let key = ZStreamNative.randomBytes(32)
        let plaintext = "secret".data(using: .utf8)!
        let ciphertext = ZStreamNative.aesGcmEncrypt(plaintext, withKey: key, aad: nil)
        let recovered = ZStreamNative.aesGcmDecrypt(ciphertext, withKey: key, aad: nil)
        XCTAssertEqual(plaintext, recovered)
    }
}
```

### Integration tests
```swift
func testAsperaResolver() {
    let result = ZStreamNative.asperaResolve("550582", type: "movie", season: "", episode: "")
    XCTAssertFalse(result.isEmpty)
    // Verify JSON response
}
```

## Troubleshooting

**Error**: `'openssl/ssl.h' file not found`
- **Solution**: Run `./scripts/build-boringssl.sh` before `xcodegen generate` / opening the project — `ThirdParty/BoringSSL.xcframework` must exist first.

**Error**: `Use of undeclared identifier 'std::string'`
- **Solution**: Ensure the file is `.mm` (Objective-C++), not `.m`.

**Error**: `EVP_AEAD_CTX`/`EVP_aead_aes_256_gcm` undeclared
- **Solution**: You're linking against stock OpenSSL headers, not BoringSSL's — check `HEADER_SEARCH_PATHS`/the xcframework actually got linked.

### Runtime issues

**HTTPS requests failing**: `net_common.cpp` does raw-socket TLS with `SSL_VERIFY_NONE` (matches Android) — check host/DNS reachability, not cert validation.

**Source resolver returning `"null"`/`"[]"`**: Check that the JSON parsing in each resolver matches the current upstream API response shape.

**Fontaine `resolveArtemisKeyless` getting 403s**: the server-side gate parses `androidMinVersion` out of the `User-Agent` header, expecting an `X/<version>` prefix — `artemis_user_agent()` currently sends `ZStreami0S/3.0.0`. If the gate is strict about a specific prefix or version floor, this may need to match what the backend actually expects for non-Android clients.

## Security Considerations

- AES-256-GCM provides authenticated encryption
- HMAC-SHA-256 verifies API request signatures
- Ensure API keys/tokens are not logged
- Keep the pinned BoringSSL commit updated for security patches (bump `BORINGSSL_COMMIT` in `scripts/build-boringssl.sh`, keeping it in sync with the Android repo's `CMakeLists.txt`)
