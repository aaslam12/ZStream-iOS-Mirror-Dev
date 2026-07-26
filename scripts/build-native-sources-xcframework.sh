#!/usr/bin/env bash
# Builds the private ZStreamNativeSources Swift package (the native stream
# resolvers) into a stripped, binary-only .xcframework — no .swift/.cpp/.h
# source, just the compiled module. This is the ONLY artifact that should
# ever leave this machine for the resolver internals; see
# scripts/publish-dev-mirror.sh for how it's handed to another dev.
#
# This builds via Packages/ZStreamNativeSources/XCFrameworkProject, a real
# Xcode project with a Framework target (NOT the SwiftPM package scheme).
# SwiftPM package targets can't mix Swift and C/C++/ObjC++ in one target, so
# the package itself keeps Swift and C++ as two separate targets — fine for
# a normal source build, but the compiled .swiftmodule from that split then
# permanently records a hard dependency on the internal C++ target's module
# name, which isn't shippable/resolvable outside this package build. A real
# Xcode Framework target compiles everything into one module with no such
# internal boundary. Same source files, referenced directly (not copied).
#
# The .xcframework itself is assembled BY HAND below (plain mkdir/cp + a
# hand-written Info.plist) instead of via `xcodebuild -create-xcframework`.
# That tool demands at least one .swiftinterface file per Swift module dir,
# which requires BUILD_LIBRARY_FOR_DISTRIBUTION=YES — but this target uses a
# bridging header (SWIFT_OBJC_BRIDGING_HEADER) to expose the C++ symbols to
# Swift, and Xcode flatly refuses "bridging headers with module interfaces"
# together. Since we don't need ABI-stable textual interfaces anyway (same
# toolchain builds both this and the app), skip -create-xcframework's
# validation and write the well-known xcframework layout ourselves.
#
# Usage: scripts/build-native-sources-xcframework.sh [output-dir]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/Packages/ZStreamNativeSources/XCFrameworkProject"
OUT_DIR="${1:-$REPO_ROOT/build/xcframeworks}"
SCHEME="ZStreamNativeSources"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/native-sources-xcframework.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

pushd "$PROJECT_DIR" >/dev/null
xcodegen generate
popd >/dev/null

archive_slice() {
    local destination="$1"
    local archive_path="$2"
    # NSUnbufferedIO=YES: xcodebuild fully buffers its stdout when it isn't a
    # tty (always true in CI), so without this nothing shows up in the log
    # until the buffer fills or the whole build finishes — this step runs
    # two full archives back-to-back, long enough for that delay to be very
    # visible in the Actions UI.
    NSUnbufferedIO=YES xcodebuild archive \
        -project "$PROJECT_DIR/ZStreamNativeSources.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -archivePath "$archive_path" \
        SKIP_INSTALL=NO \
        CODE_SIGNING_ALLOWED=NO \
        | xcbeautify --renderer github-actions
}

echo "==> Archiving for iOS device"
archive_slice "generic/platform=iOS" "$WORK/ios.xcarchive"

echo "==> Archiving for iOS Simulator"
archive_slice "generic/platform=iOS Simulator" "$WORK/ios-sim.xcarchive"

find_framework() {
    find "$1/Products" -type d -name "${SCHEME}.framework" | head -1
}

IOS_FRAMEWORK=$(find_framework "$WORK/ios.xcarchive")
SIM_FRAMEWORK=$(find_framework "$WORK/ios-sim.xcarchive")

for f in "$IOS_FRAMEWORK" "$SIM_FRAMEWORK"; do
    [[ -n "$f" && -d "$f" ]] || { echo "error: could not find ${SCHEME}.framework under archive Products" >&2; exit 1; }
done

echo "==> Device framework: $IOS_FRAMEWORK"
find "$IOS_FRAMEWORK" -maxdepth 2
echo "==> Simulator framework: $SIM_FRAMEWORK"
find "$SIM_FRAMEWORK" -maxdepth 2

mkdir -p "$OUT_DIR"
XCFRAMEWORK="$OUT_DIR/${SCHEME}.xcframework"
rm -rf "$XCFRAMEWORK"

IOS_SLICE_ID="ios-arm64"
SIM_SLICE_ID="ios-arm64_x86_64-simulator"

echo "==> Assembling xcframework by hand"
mkdir -p "$XCFRAMEWORK/$IOS_SLICE_ID" "$XCFRAMEWORK/$SIM_SLICE_ID"
cp -R "$IOS_FRAMEWORK" "$XCFRAMEWORK/$IOS_SLICE_ID/"
cp -R "$SIM_FRAMEWORK" "$XCFRAMEWORK/$SIM_SLICE_ID/"

cat > "$XCFRAMEWORK/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>LibraryIdentifier</key>
			<string>${IOS_SLICE_ID}</string>
			<key>LibraryPath</key>
			<string>${SCHEME}.framework</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
		<dict>
			<key>LibraryIdentifier</key>
			<string>${SIM_SLICE_ID}</string>
			<key>LibraryPath</key>
			<string>${SCHEME}.framework</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

echo "wrote $XCFRAMEWORK"
echo
echo "Sanity check — this should show NO .swift/.cpp/.mm implementation files."
echo "(A public ZStreamNative.h with just method signatures is expected and fine —"
echo "that's the ObjC bridge interface, not the crypto/resolver logic itself.)"
find "$XCFRAMEWORK" -type f \( -name "*.swift" -o -name "*.cpp" -o -name "*.mm" \) -print
