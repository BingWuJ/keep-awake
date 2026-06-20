---
name: keep-awake
description: >-
  Keep macOS awake while AI agents / long tasks run — no display sleep, no system sleep, and
  optionally no sleep even with the lid closed (clamshell), external display unplugged, or on battery.
  Three modes: super (never sleep until stopped), flex (awake only while the agent works, auto-released
  when it stops), normal (display only — sleeps when lid closes). Use when the user wants to prevent the
  Mac from sleeping, keep the screen on, stay awake with the lid closed, or keep an agent running unattended.
  Triggers / 触发词: keep awake, prevent sleep, never sleep, stop mac sleeping, keep display on, stay awake
  with lid closed, clamshell, caffeinate, don't let my computer sleep, 防休眠, 防止系统休眠, 合盖不休眠,
  保持唤醒, 让电脑不休眠, 挂机不休眠, 别息屏, 别休眠.
---

# keep-awake — keep a Mac awake while AI agents work (macOS only)

The script `scripts/keep-awake.sh` is the single entry point. State lives in `~/.keep-awake/`.

## Two levers (the whole mechanism)

- `caffeinate -dims` — blocks display / idle / disk / system sleep. No privileges. Cannot block lid-close sleep.
- `pmset disablesleep` — blocks all sleep incl. lid-close / on-battery. Needs root via a one-time passwordless `sudoers` rule.

## Modes → run on user intent (don't re-ask if the intent is clear)

| User wants | Command | Behavior | Needs lid auth |
|---|---|---|---|
| Never sleep until I stop (lid/unplug/battery too) | `bash scripts/keep-awake.sh on super` | levers 1+2 always on | yes |
| Awake only while you work, sleep when idle | `bash scripts/keep-awake.sh on flex` | levers 1+2 while working; auto-release on Stop | yes |
| Just don't dim/sleep while I'm here | `bash scripts/keep-awake.sh on normal` | lever 1 only; lid-close sleeps | no |
| Stop / allow sleep | `bash scripts/keep-awake.sh off` | resets everything incl. disablesleep | — |

Default recommendation when intent is vague: **flex** (protects while working, saves power when idle).

## Hard rules

- ❌ Never fake "awake with lid closed" — if `pmset disablesleep` auth is missing, say so honestly and print the auth guide. `on super` / `on flex` already do this.
- ❌ Never leave `disablesleep` stuck on — `off` and the flex Stop hook always reset it to 0.
- ⚠️ Before super (or flex while working): tell the user closed-lid + no external display runs hot, and it never sleeps on battery — run `off` when done.
- ⚠️ For normal mode with an external display + power: closing the lid enters macOS clamshell mode and stays awake — a hardware behavior, not controllable here.
- `arm` / `disarm` are hook-internal; never call them manually.

## Flex auto-cycle (optional, Claude Code only)

`on flex` safe-merges two hooks into `~/.claude/settings.json`:
`UserPromptSubmit → keep-awake.sh arm` (engage while working) and `Stop → keep-awake.sh disarm` (release when idle).
This makes protection follow the agent's work automatically. `off` removes them.

## Menu bar / status indicators (optional)

- `scripts/menubar.py` (needs `rumps`) shows the mode in the macOS menu bar and lets the user switch/stop by click. Installed via `install.sh` (LaunchAgent `com.keep-awake.menubar`). Note: never use `rumps.alert` (modal) in it — it freezes the menu; surface hints in the dropdown detail row.
- `scripts/statusline.sh` is an optional Claude Code `statusLine` provider.

## Platform

macOS only (relies on `caffeinate` / `pmset`). Apple Silicon + Intel. The script exits with a clear message on non-Darwin systems.
