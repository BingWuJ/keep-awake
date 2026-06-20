#!/usr/bin/env bash
# uninstall.sh — remove the keep-awake menu-bar LaunchAgent and reset state.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.keep-awake.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_N="$(id -u)"

echo "→ Stopping any active keep-awake protection…"
bash "$REPO_DIR/scripts/keep-awake.sh" off >/dev/null 2>&1 || true

echo "→ Removing the menu-bar LaunchAgent…"
launchctl bootout "gui/$UID_N" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "✅ Uninstalled."
echo "   The lid-proof authorization (if you set it up) is left in place. Remove it with:"
echo "     sudo rm /etc/sudoers.d/keep-awake"
