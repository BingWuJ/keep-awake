#!/usr/bin/env bash
# statusline.sh — optional Claude Code status-line provider.
# Wire it via settings.json: {"statusLine": {"type": "command", "command": "bash /path/to/statusline.sh"}}
# Reads stdin JSON (session info) and prints one line: current keep-awake state + dir + model.
# Fast and never errors. Uses jq if available for the stdin JSON.

input="$(cat)"
STATE_DIR="$HOME/.keep-awake"

mode="$(cat "$STATE_DIR/mode" 2>/dev/null || true)"

running=0
if [[ -f "$STATE_DIR/caffeinate.pid" ]]; then
  pid="$(cat "$STATE_DIR/caffeinate.pid" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && running=1
fi

case "$mode" in
  super)  state="● Awake (Super)";;
  flex)   if [[ $running -eq 1 ]]; then state="● Awake (Flex)"; else state="○ Flex idle"; fi;;
  normal) state="● Awake (Normal)";;
  *)      state="○ Sleep OK";;
esac

if command -v jq >/dev/null 2>&1; then
  dir="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null || true)"
  model="$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // ""' 2>/dev/null || true)"
else
  dir=""; model=""
fi

out="$state"
[[ -n "$dir" ]] && out="$out  ·  $(basename "$dir")"
[[ -n "$model" ]] && out="$out  ·  $model"
printf '%s' "$out"
