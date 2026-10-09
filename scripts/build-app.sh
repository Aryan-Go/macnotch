#!/bin/bash
# Builds MacNotch.app into ./dist. No Xcode project required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="MacNotch"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Vendored MediaRemote helper (perl script + framework).
cp "$ROOT/Sources/MacNotch/Resources/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ROOT/Sources/MacNotch/Resources/MediaRemoteAdapter.framework" "$APP/Contents/Resources/"
cp "$ROOT/Sources/MacNotch/Resources/MediaRemoteAdapter.LICENSE" "$APP/Contents/Resources/"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/Resources/MediaRemoteAdapter.framework" >/dev/null 2>&1 || true
codesign --force --sign - "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP"
echo "    Run it with: open \"$APP\""
