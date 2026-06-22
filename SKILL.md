---
name: keep-awake
description: >-
  Keep Windows 11 awake while AI agents / long tasks run — no display sleep, no system sleep, and
  optionally no sleep even with the lid closed, external display unplugged, or on battery.
  Three modes: super (never sleep until stopped), flex (awake only while the agent works, auto-released
  when it stops), normal (display only — sleeps when lid closes). Use when the user wants to prevent
  Windows from sleeping, keep the screen on, stay awake with the lid closed, or keep an agent running unattended.
  Triggers / 触发词: keep awake, prevent sleep, never sleep, stop windows sleeping, keep display on, stay awake
  with lid closed, clamshell, don't let my computer sleep, 防休眠, 防止系统休眠, 合盖不休眠,
  保持唤醒, 让电脑不休眠, 挂机不休眠, 别息屏, 别休眠.
---

# keep-awake — keep a Windows 11 PC awake while AI agents work (Windows only)

The script `scripts/keep-awake.ps1` is the single entry point. State lives in `~/.keep-awake/`.

## Two levers (the whole mechanism)

- `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)` — held by a hidden
  `awake-watcher.ps1` daemon. Blocks display / idle / disk / system sleep. No privileges. Cannot block lid-close sleep.
- `powercfg` standby/hibernate/lid timeout changes — blocks all sleep incl. lid-close / on-battery. Needs admin,
  implemented through a one-time UAC-authorized scheduled task `keep-awake-strong` (passwordless thereafter).

## Modes → run on user intent (don't re-ask if the intent is clear)

| User wants | Command | Behavior | Needs lid auth |
|---|---|---|---|
| Never sleep until I stop (lid/unplug/battery too) | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 on super` | levers 1+2 always on | yes |
| Awake only while you work, sleep when idle | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 on flex` | levers 1+2 while working; auto-release on Stop | yes |
| Just don't dim/sleep while I'm here | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 on normal` | lever 1 only; lid-close sleeps | no |
| Stop / allow sleep | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 off` | resets everything incl. power plan | — |

Default recommendation when intent is vague: **flex** (protects while working, saves power when idle).

## Hard rules

- ❌ Never fake "awake with lid closed" — if the `keep-awake-strong` task is not registered, say so honestly and print the auth guide. `on super` / `on flex` already do this.
- ❌ Never leave power-plan changes stuck on — `off` and the flex Stop hook always restore the backed-up standby/hibernate/lid values.
- ⚠️ Before super (or flex while working): tell the user closed-lid + no external display runs hot, and it never sleeps on battery — run `off` when done.
- `arm` / `disarm` are hook-internal; never call them manually.

## Flex auto-cycle (optional, pi / Claude Code only)

`on flex` safe-merges two hooks into `~/.pi/agent/settings.json` and `~/.claude/settings.json`:
`UserPromptSubmit → keep-awake.ps1 arm` (engage while working) and `Stop → keep-awake.ps1 disarm` (release when idle).
This makes protection follow the agent's work automatically. `off` removes them.

## Status line (optional)

- `scripts/statusline.ps1` is an optional pi / Claude Code `statusLine` provider.
- Wire it via settings.json: `{"statusLine": {"type": "command", "command": "pwsh -NoProfile -File <repo>\\scripts\\statusline.ps1"}}`

## Platform

Windows 11 only (relies on `SetThreadExecutionState` / `powercfg`). PowerShell 7 recommended; Windows PowerShell 5.1 may work for core CLI but the scheduled task runs under pwsh. Running on non-Windows systems is unsupported and will likely fail with P/Invoke or `powercfg` errors.
