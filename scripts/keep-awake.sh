#!/usr/bin/env bash
# keep-awake.sh — keep macOS awake while AI agents / long tasks run.
# No display sleep, no idle sleep, optionally no sleep even with the lid closed.
#
# Two levers:
#   1) caffeinate -dims    blocks display + idle + disk + system sleep. No privileges.
#                          (Cannot block lid-close sleep.)
#   2) pmset disablesleep  blocks ALL sleep incl. lid-close / on-battery. Needs root
#                          (one-time passwordless sudoers authorization).
#
# Three named modes:
#   super   caffeinate + disablesleep always on  -> never sleeps (lid/unplug too), until `off`.
#   flex    caffeinate + disablesleep only WHILE working; auto-released when the agent stops.
#           Driven by Claude Code hooks (UserPromptSubmit -> arm, Stop -> disarm). Optional.
#   normal  caffeinate only -> stays awake with lid open, sleeps when lid closed.
#
# Usage:
#   keep-awake.sh on <super|flex|normal>     start a mode
#   keep-awake.sh off [--sleep-now]          stop everything (+ optionally sleep right now)
#   keep-awake.sh status                     print current state
#   keep-awake.sh arm | disarm               (hook-internal, do not call manually)
#   keep-awake.sh install-hook | uninstall-hook

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ keep-awake supports macOS only (it relies on caffeinate / pmset)." >&2
  exit 1
fi

STATE_DIR="$HOME/.keep-awake"
PID_FILE="$STATE_DIR/caffeinate.pid"
MODE_FILE="$STATE_DIR/mode"
INFO_FILE="$STATE_DIR/info"
STRONG_FILE="$STATE_DIR/strong"   # present = disablesleep=1 (lid-proof) is currently active
SETTINGS="$HOME/.claude/settings.json"   # Claude Code settings (only used by hook install)
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
mkdir -p "$STATE_DIR"

now() { date "+%Y-%m-%d %H:%M:%S"; }
cur_mode() { cat "$MODE_FILE" 2>/dev/null || echo "-"; }
friendly() { case "$1" in super) echo "Super";; flex) echo "Flex";; normal) echo "Normal";; *) echo "$1";; esac; }

# ---- Lever 1: caffeinate ----------------------------------------------------
running_pid() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] || return 1
  if kill -0 "$pid" 2>/dev/null; then echo "$pid"; return 0; fi
  return 1
}
start_caffeinate() {
  running_pid >/dev/null && return 0
  # detach from this shell so it survives the shell exiting
  nohup caffeinate -dims </dev/null >/dev/null 2>&1 &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PID_FILE"
}
stop_caffeinate() {
  local pid
  if pid="$(running_pid)"; then kill "$pid" 2>/dev/null || true; fi
  rm -f "$PID_FILE"
}

# ---- Lever 2: pmset disablesleep (needs passwordless sudo) -------------------
strong_on()  { sudo -n pmset -a disablesleep 1 >/dev/null 2>&1 && { touch "$STRONG_FILE"; return 0; } || return 1; }
strong_off() { sudo -n pmset -a disablesleep 0 >/dev/null 2>&1 && { rm -f "$STRONG_FILE"; return 0; } || return 1; }

print_auth_guide() {
  echo "🔑 The 'awake with lid closed' feature needs a one-time authorization (passwordless thereafter)."
  echo "   Paste this whole line into Terminal and enter your login password once"
  echo "   (it only whitelists toggling lid-sleep — nothing else):"
  echo
  echo "  echo \"\$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\" | sudo tee /etc/sudoers.d/keep-awake >/dev/null && sudo chmod 440 /etc/sudoers.d/keep-awake && sudo visudo -cf /etc/sudoers.d/keep-awake && echo OK"
  echo
  echo "   Then run the mode again. (Revoke: sudo rm /etc/sudoers.d/keep-awake)"
}

# ---- Claude Code hooks (safe-merge settings.json, idempotent) ----------------
install_hook() {
  command -v python3 >/dev/null 2>&1 || { echo "ℹ️  python3 not found; skipping Claude Code hook install."; return 0; }
  python3 - "$SETTINGS" "$SELF" <<'PY'
import json, os, sys
settings_path, script = sys.argv[1], sys.argv[2]
s = {}
if os.path.exists(settings_path):
    with open(settings_path) as f: s = json.load(f)
hooks = s.setdefault("hooks", {})
def ensure(event, arg):
    arr = hooks.setdefault(event, [])
    cmd = f'bash "{script}" {arg} >/dev/null 2>&1 || true'
    for entry in arr:
        for h in entry.get("hooks", []):
            if script in h.get("command", "") and f" {arg} " in (h.get("command","")+" "):
                return
    arr.append({"hooks": [{"type": "command", "command": cmd}]})
ensure("UserPromptSubmit", "arm")
ensure("Stop", "disarm")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False); f.write("\n")
PY
}
uninstall_hook() {
  [[ -f "$SETTINGS" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$SETTINGS" "$SELF" <<'PY'
import json, os, sys
settings_path, script = sys.argv[1], sys.argv[2]
with open(settings_path) as f: s = json.load(f)
hooks = s.get("hooks", {})
for event in ("UserPromptSubmit", "Stop"):
    arr = hooks.get(event)
    if not arr: continue
    new = []
    for entry in arr:
        kept = [h for h in entry.get("hooks", []) if script not in h.get("command", "")]
        if kept:
            entry = dict(entry); entry["hooks"] = kept; new.append(entry)
        elif "hooks" not in entry:
            new.append(entry)
    if new: hooks[event] = new
    else: hooks.pop(event, None)
if not hooks: s.pop("hooks", None)
with open(settings_path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False); f.write("\n")
PY
}

# ---- Commands ---------------------------------------------------------------
cmd_on() {
  local mode="${1:-}"
  case "$mode" in super|flex|normal) ;; *) echo "❌ usage: on <super|flex|normal>"; exit 1;; esac
  echo "$mode" > "$MODE_FILE"
  { echo "mode=$mode"; echo "started=$(now)"; } > "$INFO_FILE"

  case "$mode" in
    normal)
      uninstall_hook >/dev/null 2>&1 || true
      strong_off >/dev/null 2>&1 || true
      start_caffeinate
      echo "🔆 NORMAL: no display/idle sleep while the lid is open; sleeps normally when you close the lid."
      echo "   (Note: with an external display + power, closing the lid enters macOS clamshell mode and"
      echo "    stays awake — that is a hardware behavior this tool cannot override.)"
      ;;
    super)
      uninstall_hook >/dev/null 2>&1 || true
      start_caffeinate
      if strong_on; then
        echo "🛡️ SUPER: never sleeps — lid closed / external display unplugged / on battery — until you run 'off'."
        echo "   ⚠️ Closed-lid with no external display runs hot under load; it also never sleeps on battery. Run 'off' when done."
      else
        echo "🔆 Basic anti-sleep is on, but SUPER's 'awake with lid closed' needs one more step:"
        print_auth_guide
      fi
      ;;
    flex)
      install_hook
      start_caffeinate
      if strong_on; then
        echo "🛡️ FLEX: awake while working (lid closed too); auto-released when the agent stops, re-armed on your next message."
      else
        echo "🔆 FLEX basic anti-sleep is on while working; 'awake with lid closed' needs one more step:"
        print_auth_guide
      fi
      ;;
  esac
}

cmd_off() {
  local sleep_now="no"
  [[ "${1:-}" == "--sleep-now" ]] && sleep_now="yes"
  stop_caffeinate
  uninstall_hook >/dev/null 2>&1 || true
  if [[ -f "$STRONG_FILE" ]]; then
    if strong_off; then
      echo "🌙 Stopped (incl. lid-proof). Normal sleep behavior restored."
    else
      echo "⚠️ caffeinate stopped, but disablesleep needs privileges to reset. Run: sudo pmset -a disablesleep 0"
    fi
  else
    echo "🌙 Stopped. Normal sleep behavior restored."
  fi
  rm -f "$MODE_FILE" "$INFO_FILE"
  if [[ "$sleep_now" == "yes" ]]; then
    echo "💤 Sleeping now…"
    pmset sleepnow >/dev/null 2>&1 || echo "⚠️ pmset sleepnow failed; please sleep manually."
  fi
}

# UserPromptSubmit hook: only in flex mode, engage protection while working (silent).
cmd_arm() {
  [[ "$(cur_mode)" == "flex" ]] || exit 0
  start_caffeinate
  strong_on >/dev/null 2>&1 || true
  exit 0
}
# Stop hook: only in flex mode, release when the agent stops; keep mode/hooks (silent).
cmd_disarm() {
  [[ "$(cur_mode)" == "flex" ]] || exit 0
  stop_caffeinate
  strong_off >/dev/null 2>&1 || true
  exit 0
}

cmd_status() {
  local pid mode; mode="$(cur_mode)"
  if pid="$(running_pid)"; then
    echo "State: 🔆 AWAKE · $(friendly "$mode")    caffeinate pid: $pid"
    [[ -f "$INFO_FILE" ]] && grep -E '^started=' "$INFO_FILE" | sed 's/^/  /'
  else
    echo "State: 🌙 not awake (normal sleep)    last mode: $(friendly "$mode")"
  fi
  if [[ -f "$STRONG_FILE" ]] || pmset -g 2>/dev/null | grep -qiE 'disablesleep.*1|SleepDisabled.*1'; then
    echo "Lid-proof: 🛡️ ON (awake with lid closed / display unplugged)"
  else
    echo "Lid-proof: — off (sleeps when lid closed)"
  fi
  echo "--- pmset assertions ---"
  pmset -g assertions 2>/dev/null | grep -iE 'PreventUserIdleDisplaySleep|PreventUserIdleSystemSleep|caffeinate' | sed 's/^/  /' || true
}

# ---- Entry ------------------------------------------------------------------
case "${1:-}" in
  on)             shift; cmd_on "$@";;
  off)            shift; cmd_off "$@";;
  status|"")      cmd_status;;
  arm)            cmd_arm;;
  disarm)         cmd_disarm;;
  install-hook)   install_hook; echo "✅ hooks installed";;
  uninstall-hook) uninstall_hook; echo "✅ hooks removed";;
  *) echo "unknown command: $1"; echo "usage: keep-awake.sh on <super|flex|normal> | off | status"; exit 1;;
esac
