# C++ Sources Ported from Android to iOS

## Overview
Successfully ported all C++ plugin sources from `ZStream-Android` to `z-stream-ios`. All JNI Android-specific code has been removed and replaced with iOS-compatible implementations.

## Directory Structure
```
ZStream/Sources/Native/
├── cpp/                          # C++ implementation files
│   ├── crypto_impl.h            # Crypto interface (SHA-256, HMAC, AES-256-GCM, RAND)
│   ├── crypto_impl.cpp          # BoringSSL-based implementations
│   ├── net_common.h             # HTTP utilities interface
│   ├── net_common.cpp           # Raw HTTPS, chunked encoding, redirects
│   ├── module.modulemap         # Module map for C++ imports
│   ├── aphrodite.cpp            # Source resolver
│   ├── aspera.cpp               # Source resolver
│   ├── cosmic.cpp               # Source resolver
│   ├── fontaine.cpp             # Source resolver (Artemis keyless)
│   ├── magnolia.cpp             # Source resolver
│   ├── nesterov.cpp             # Source resolver
│   ├── shibuya.cpp              # Source resolver
│   ├── stellar.cpp              # Source resolver
│   └── tokyo.cpp                # Source resolver
├── objcpp/                       # Objective-C++ bridge layer
│   ├── ZStreamNative.h          # Obj-C interface to C++ functions
│   └── ZStreamNative.mm         # Obj-C++ implementation
└── ZStream-Bridging-Header.h    # Swift bridging header
```

## Ported C++ Files (11 total)

### Crypto & Network Layer
- **crypto_impl.h/cpp**: Cryptographic functions (SHA-256, HMAC-SHA-256, AES-256-GCM encrypt/decrypt, random bytes)
- **net_common.h/cpp**: HTTP request handling with redirect support and chunked transfer encoding

### Source Resolvers (9 total)
1. **aphrodite.cpp** - Source resolver with JSON parsing
2. **aspera.cpp** - TMDB-based source resolution via enc-dec.app API
3. **cosmic.cpp** - Source resolver 
4. **fontaine.cpp** - Artemis keyless source resolver (with modified user agent)
5. **magnolia.cpp** - Source resolver
6. **nesterov.cpp** - Source resolver
7. **shibuya.cpp** - Source resolver
8. **stellar.cpp** - Source resolver
9. **tokyo.cpp** - Source resolver with Android user agent (updated for iOS)

## Conversion Changes

### Removed
- `#include <jni.h>` - All JNI headers removed
- `JNIEXPORT`, `JNICALL` keywords - Converted to `extern "C"`
- `JNIEnv*` parameters - Removed from all functions
- `jstring`, `jobject`, `jclass` types - Replaced with `std::string`
- All `env->*` calls (GetStringUTFChars, NewStringUTF, etc.)
- JNI exception checking patterns
- Android system property calls (`__system_property_get`)
- Integrity checks (`integrity_ok()` calls)

### Modified
- **fontaine.cpp**: 
  - Replaced `artemis_host_version_name(JNIEnv*)` with simplified version returning hardcoded "1.0.0"
  - Replaced `artemis_user_agent(JNIEnv*)` with iOS version building "ZStreami0S/" user agent
  - Simplified `resolveArtemisKeyless()` parameter handling from JNI to direct std::string

- **tokyo.cpp**: Updated Android user agent string to iOS-compatible format

### Preserved
- All core algorithm implementations
- HTTP request logic (HTTPS, redirects, chunked encoding)
- Cryptographic functions (crypto_impl)
- JSON parsing utilities in source resolvers
- Cache implementations with thread-safe mutexes

## Bridging Layer

### ZStreamNative.h (Objective-C Interface)
Exposes 9 source resolver functions + 5 crypto utilities to Swift:
- Resolvers: `asperaResolve`, `aphroditeResolve`, `cosmicResolve`, `stellarResolve`, `fontaineResolve` (nativeResolve/auroraResolve), `magnoliaResolve`, `nesterovResolve`, `shibuyaResolve`, `tokyoResolve`
- Crypto: `sha256`, `hmacSha256`, `aesGcmEncrypt`, `aesGcmDecrypt`, `randomBytes`

### ZStreamNative.mm (Objective-C++ Implementation)
- String conversion helpers (NSString ↔ std::string)
- Wrapper methods for all C++ functions
- Memory management for crypto operations
- Thread-safe bridging

### ZStream-Bridging-Header.h
Exposes ZStreamNative.h to Swift code

## Build Integration Notes

### Required Framework Dependencies
- Foundation (NSString, NSData, NSUInteger)
- Darwin/os/log (logging)

### C++ Standard
- C++17 (uses `std::optional`, `auto`, etc.)

### External Dependencies Retained
- BoringSSL (crypto_impl.cpp) - **Must be integrated via CocoaPods/SPM**
- OpenSSL headers (net_common.cpp)

### No Android-Specific Dependencies
All Android system dependencies removed:
- No android/log.h
- No JNI libraries
- No android system properties

## Next Steps

1. **Configure Xcode Build Settings**:
   - Enable C++17 support for the Native target
   - Link against BoringSSL (or OpenSSL/LibreSSL alternative)
   - Add header search paths for crypto libraries

2. **Integrate Crypto Library**:
   - BoringSSL via CocoaPods with spec:
     ```ruby
     pod 'BoringSSL', :git => 'https://github.com/google/boringssl.git'
     ```
   - Or switch to `CommonCrypto` framework (already available on iOS)

3. **Update Swift Code**:
   - Import the bridging header where needed
   - Call ZStreamNative methods for source resolution

4. **Testing**:
   - Unit tests for crypto functions
   - Integration tests for HTTP requests
   - End-to-end tests for source resolvers
