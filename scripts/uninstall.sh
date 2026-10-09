#!/bin/bash
# Removes MacNotch, its login item, and its preferences.
set -euo pipefail

APP_NAME="MacNotch"
TARGET="/Applications/$APP_NAME.app"
AGENT_LABEL="com.macnotch.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

echo "==> Stopping MacNotch"
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Removing files"
rm -rf "$TARGET"
rm -f "$AGENT_PLIST"

echo "Done."
