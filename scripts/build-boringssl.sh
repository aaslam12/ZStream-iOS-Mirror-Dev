#!/usr/bin/env bash
# Builds BoringSSL for iOS (device arm64 + simulator arm64/x86_64), pinned to
# the same commit the Android plugin uses, and packages the result as
# ThirdParty/BoringSSL.xcframework. macOS + Xcode command-line tools only.
#
# Not committed to the repo — run locally before `xcodegen generate`, or let
# CI run it (see .github/workflows/build-ipa.yml). Safe to re-run: skips
# work that's already done for the pinned commit.
set -euo pipefail

# Keep this in sync with zstream-plugin/plugin/src/main/cpp/CMakeLists.txt
# in the Android repo — same BoringSSL commit on both platforms.
BORINGSSL_COMMIT="a945a3ea4cdf8cd683a9d3ad3a66bd3f04a514e6"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/third_party/boringssl-src"
BUILD_DIR="$ROOT_DIR/third_party/build"
OUT_XCFRAMEWORK="$ROOT_DIR/ThirdParty/BoringSSL.xcframework"
STAMP_FILE="$BUILD_DIR/.commit-stamp"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "error: this script builds Apple static libraries and must run on macOS." >&2
    exit 1
fi

for tool in cmake ninja perl go xcodebuild lipo libtool; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' not found on PATH." >&2
        exit 1
    fi
done

if [[ -d "$OUT_XCFRAMEWORK" && -f "$STAMP_FILE" && "$(cat "$STAMP_FILE")" == "$BORINGSSL_COMMIT" ]]; then
    echo "BoringSSL.xcframework already built for $BORINGSSL_COMMIT — skipping."
    exit 0
fi

echo "==> Fetching BoringSSL @ $BORINGSSL_COMMIT"
mkdir -p "$ROOT_DIR/third_party"
if [[ ! -d "$SRC_DIR/.git" ]]; then
    git clone https://boringssl.googlesource.com/boringssl "$SRC_DIR"
fi
git -C "$SRC_DIR" fetch --depth 1 origin "$BORINGSSL_COMMIT"
git -C "$SRC_DIR" checkout --detach FETCH_HEAD

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# "key:IOS_PLATFORM" pairs for scripts/ios.toolchain.cmake. Avoid associative
# arrays here — macOS ships bash 3.2 as /usr/bin/env bash, which doesn't
# support `declare -A`.
PLATFORMS="device-arm64:OS64 sim-arm64:SIMULATORARM64 sim-x86_64:SIMULATOR64"

for pair in $PLATFORMS; do
    key="${pair%%:*}"
    ios_platform="${pair##*:}"
    build_subdir="$BUILD_DIR/$key"
    echo "==> Building BoringSSL for $key ($ios_platform)"
    cmake -GNinja \
        -S "$SRC_DIR" \
        -B "$build_subdir" \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT_DIR/scripts/ios.toolchain.cmake" \
        -DIOS_PLATFORM="$ios_platform" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_SHARED_LIBS=OFF
    # Redirected to a log file, not streamed live: ninja emits ~400 compile
    # lines per slice (~1200 total across 3 slices) in quick succession,
    # which is enough volume to make GitHub Actions' live log viewer fail to
    # open the step while it's still running. Dump the tail on failure.
    build_log="$build_subdir/build.log"
    if ! cmake --build "$build_subdir" --target crypto --target ssl -- -j"$(sysctl -n hw.ncpu)" > "$build_log" 2>&1; then
        echo "error: build failed for $key — last 200 lines of $build_log:" >&2
        tail -200 "$build_log" >&2
        exit 1
    fi

    libcrypto_a="$(find "$build_subdir" -name libcrypto.a -print -quit)"
    libssl_a="$(find "$build_subdir" -name libssl.a -print -quit)"
    if [[ -z "$libcrypto_a" || -z "$libssl_a" ]]; then
        echo "error: libcrypto.a/libssl.a not found under $build_subdir — cmake build did not produce them." >&2
        exit 1
    fi

    # Merge crypto+ssl into one static lib per platform slice.
    libtool -static -o "$build_subdir/libboringssl.a" "$libcrypto_a" "$libssl_a"
done

echo "==> Fattening simulator slices (arm64 + x86_64)"
SIM_FAT_DIR="$BUILD_DIR/sim-fat"
mkdir -p "$SIM_FAT_DIR"
lipo -create \
    "$BUILD_DIR/sim-arm64/libboringssl.a" \
    "$BUILD_DIR/sim-x86_64/libboringssl.a" \
    -output "$SIM_FAT_DIR/libboringssl.a"

echo "==> Assembling xcframework headers"
HEADERS_DIR="$BUILD_DIR/headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp -R "$SRC_DIR/include/openssl" "$HEADERS_DIR/"

echo "==> Creating $OUT_XCFRAMEWORK"
rm -rf "$OUT_XCFRAMEWORK"
mkdir -p "$ROOT_DIR/ThirdParty"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/device-arm64/libboringssl.a" -headers "$HEADERS_DIR" \
    -library "$SIM_FAT_DIR/libboringssl.a" -headers "$HEADERS_DIR" \
    -output "$OUT_XCFRAMEWORK"

echo "$BORINGSSL_COMMIT" > "$STAMP_FILE"
echo "==> Done: $OUT_XCFRAMEWORK"
