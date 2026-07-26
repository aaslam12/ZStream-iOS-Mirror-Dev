#!/usr/bin/env bash
# Publishes a private "dev mirror" of this repo: everything except the
# native resolver source (ZStreamNativeSources/Sources/**), with a prebuilt
# ZStreamNativeSources.xcframework dropped in instead. The other dev clones
# the mirror repo once, runs xcodegen, and gets full Xcode build/debug —
# no more IPA hand-offs. Re-run this (and have them `git pull`) only when
# resolver internals themselves change.
#
# Usage: MIRROR_REMOTE=git@github.com:you/zstream-dev-mirror.git scripts/publish-dev-mirror.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR_REMOTE="${MIRROR_REMOTE:?set MIRROR_REMOTE to the private mirror repo git URL}"
MIRROR_BRANCH="${MIRROR_BRANCH:-development}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/publish-dev-mirror.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo "==> Building ZStreamNativeSources.xcframework"
"$REPO_ROOT/scripts/build-native-sources-xcframework.sh" "$WORK/xcframeworks"

MIRROR_DIR="$WORK/mirror"
echo "==> Copying repo (minus native resolver source) to $MIRROR_DIR"
mkdir -p "$MIRROR_DIR"
# rsync so we can exclude the private source tree and VCS/build cruft in one pass.
rsync -a \
    --exclude ".git" \
    --exclude "build" \
    --exclude "Packages/ZStreamNativeSources/Sources" \
    --exclude "Packages/ZStreamNativeSources/.build" \
    --exclude ".claude" \
    "$REPO_ROOT/" "$MIRROR_DIR/"

# Drop in the compiled framework where the app target will look for it.
cp -R "$WORK/xcframeworks/ZStreamNativeSources.xcframework" "$MIRROR_DIR/"

# Swap in the framework-based project file, replacing the source-package one.
mv "$MIRROR_DIR/project.dev-mirror.yml" "$MIRROR_DIR/project.yml"

# ZStreamNativeSources package dir now only contains Package.swift with no
# Sources/ — remove it entirely; the mirror references the xcframework instead.
rm -rf "$MIRROR_DIR/Packages/ZStreamNativeSources"

echo "==> Verifying no resolver source leaked into the mirror"
if find "$MIRROR_DIR" -path "*ZStreamNativeSources*" \( -name "*.swift" -o -name "*.cpp" -o -name "*.mm" \) | grep -q .; then
    echo "error: resolver source found in mirror output — aborting, not pushing" >&2
    find "$MIRROR_DIR" -path "*ZStreamNativeSources*" \( -name "*.swift" -o -name "*.cpp" -o -name "*.mm" \) >&2
    exit 1
fi

pushd "$MIRROR_DIR" >/dev/null
git init -q
git add -A
git -c user.name="ZStream Mirror Bot" -c user.email="noreply@z-stream.local" \
    commit -q -m "Sync dev mirror $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -q -f "$MIRROR_REMOTE" "HEAD:$MIRROR_BRANCH"
popd >/dev/null

echo "==> Pushed dev mirror to $MIRROR_REMOTE ($MIRROR_BRANCH)"
echo "The other dev: clone that repo, run 'xcodegen generate', open in Xcode, build to device."
