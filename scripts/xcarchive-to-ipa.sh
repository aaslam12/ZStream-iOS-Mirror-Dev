#!/usr/bin/env bash
# Turns an unsigned .xcarchive (built with CODE_SIGNING_ALLOWED=NO) into an
# unsigned .ipa the recipient can sign themselves.
#
# Accepts either a zipped CI artifact (e.g. ZStream.xcarchive.zip) or an
# already-extracted .xcarchive directory. The output .ipa is written next to
# the input zip/directory.
#
# Usage: scripts/xcarchive-to-ipa.sh <xcarchive.zip|xcarchive-dir> [output-name.ipa]
set -euo pipefail

IN="${1:?usage: $0 <xcarchive.zip|xcarchive-dir> [output-name.ipa]}"
OUT_NAME="${2:-}"

if [[ ! -e "$IN" ]]; then
    echo "error: $IN does not exist" >&2
    exit 1
fi
IN="$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")"
IN_DIR="$(dirname "$IN")"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/xcarchive-to-ipa.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [[ -d "$IN" ]]; then
    ARCHIVE_ROOT="$WORK/extracted"
    mkdir -p "$ARCHIVE_ROOT"
    cp -R "$IN/." "$ARCHIVE_ROOT/"
else
    ARCHIVE_ROOT="$WORK/extracted"
    mkdir -p "$ARCHIVE_ROOT"
    unzip -q "$IN" -d "$ARCHIVE_ROOT"
fi

# The archive contents might be at the root of what we extracted, or nested
# one level down inside a *.xcarchive folder — handle both.
APP_DIR=$(find "$ARCHIVE_ROOT" -maxdepth 4 -type d -path "*/Products/Applications" | head -1)
if [[ -z "$APP_DIR" ]]; then
    echo "error: could not find Products/Applications under $IN" >&2
    exit 1
fi

APP=$(find "$APP_DIR" -maxdepth 1 -name "*.app" | head -1)
if [[ -z "$APP" ]]; then
    echo "error: no .app found under $APP_DIR" >&2
    exit 1
fi

if [[ -n "$OUT_NAME" ]]; then
    [[ "$OUT_NAME" == *.ipa ]] || OUT_NAME="$OUT_NAME.ipa"
else
    OUT_NAME="$(basename "$APP" .app).ipa"
fi
OUT="$IN_DIR/$OUT_NAME"

PAYLOAD_DIR="$WORK/Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP" "$PAYLOAD_DIR/"

rm -f "$OUT"
( cd "$WORK" && zip -qry "$OUT" Payload )

echo "wrote $OUT"
echo
echo "NOTE for whoever signs this: the app's entitlements are NOT embedded"
echo "since the archive was built with CODE_SIGNING_ALLOWED=NO. They must"
echo "pass --entitlements pointing at that file when re-signing"
