#!/bin/bash
# Builds MacNotch.app into ./dist. No Xcode project required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="MacNotch"
APP_ID="com.macnotch.app"
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

echo "==> Signing (ad-hoc, stable identity)"
# macOS matches the Full Disk Access grant against the app's code requirement.
# A plain ad-hoc signature is identified by its code hash, which changes on every
# rebuild and silently invalidates the grant (tccd logs "Failed to match existing
# code requirement for subject com.macnotch.app and service
# kTCCServiceSystemPolicyAllFiles"). Pinning the requirement to the bundle
# identifier keeps the grant valid across rebuilds.
REQUIREMENT='=designated => identifier "com.macnotch.app"'
codesign --force --sign - "$APP/Contents/Resources/MediaRemoteAdapter.framework" >/dev/null 2>&1 || true
codesign --force --sign - --identifier "$APP_ID" "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
codesign --force --sign - --identifier "$APP_ID" --requirements "$REQUIREMENT" "$APP" >/dev/null 2>&1 || true

echo "==> Verifying signature"
ACTUAL="$(codesign -d -r- "$APP" 2>/dev/null | tail -n1)"
if [[ "$ACTUAL" == *"identifier \"$APP_ID\""* ]]; then
    echo "    code requirement: $ACTUAL"
else
    echo "    WARNING: app is not signed with the stable identifier requirement."
    echo "    Full Disk Access would be invalidated on the next rebuild."
    echo "    Got: $ACTUAL"
fi

echo "==> Done: $APP"
echo "    Run it with: open \"$APP\""
