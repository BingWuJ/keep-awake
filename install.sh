#!/usr/bin/env bash
# install.sh — set up the keep-awake menu-bar indicator on macOS.
# - installs the `rumps` dependency
# - registers a LaunchAgent so the menu bar icon auto-starts at login
# Core CLI (scripts/keep-awake.sh) needs nothing extra and works without this.

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ keep-awake supports macOS only." >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$REPO_DIR/scripts"
MENUBAR="$SCRIPTS/menubar.py"
LABEL="com.keep-awake.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

chmod +x "$SCRIPTS/keep-awake.sh" "$SCRIPTS/statusline.sh" 2>/dev/null || true

PY="$(command -v python3 || true)"
if [[ -z "$PY" ]]; then
  echo "⚠️  python3 not found. The CLI still works; the menu-bar icon needs Python 3."
  echo "    Install Python 3 (e.g. 'brew install python'), then re-run this script."
  exit 0
fi

echo "→ Installing rumps (menu-bar dependency)…"
"$PY" -m pip install --user rumps >/dev/null 2>&1 \
  || "$PY" -m pip install rumps >/dev/null 2>&1 \
  || { echo "⚠️  Could not install rumps automatically. Run: $PY -m pip install rumps"; }

echo "→ Registering the menu-bar LaunchAgent…"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$PY</string><string>$MENUBAR</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/keep-awake-menubar.log</string>
  <key>StandardErrorPath</key><string>/tmp/keep-awake-menubar.err</string>
</dict>
</plist>
EOF

UID_N="$(id -u)"
# bootstrap into the GUI domain — required for the menu-bar item to actually appear.
launchctl bootout "gui/$UID_N" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$UID_N" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || true

echo
echo "✅ Installed. A 'Sleep OK' indicator should appear in the top-right menu bar."
echo "   Tip: ⌘-drag it to reposition; macOS remembers the spot."
echo
echo "Use it:"
echo "  bash $SCRIPTS/keep-awake.sh on flex     # awake while working, auto-release when idle"
echo "  bash $SCRIPTS/keep-awake.sh on super    # never sleep (lid/unplug too) until 'off'"
echo "  bash $SCRIPTS/keep-awake.sh on normal   # awake with lid open only"
echo "  bash $SCRIPTS/keep-awake.sh status"
echo "  bash $SCRIPTS/keep-awake.sh off"
echo
echo "Optional 'awake with lid closed' (super/flex): one-time authorization —"
echo "  bash $SCRIPTS/keep-awake.sh on super     # prints the exact command if not yet authorized"
