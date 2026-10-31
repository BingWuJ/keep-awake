---
name: keep-awake
description: >-
  Keep a Windows 11 PC awake while AI agents / long tasks run - blocks system idle sleep
  only while on AC power, without overriding manual sleep or OS/firmware restrictions.
  The screen may turn off per Windows display timeout. Normal operation leaves lid,
  power-button and power-plan settings unchanged; legacy restoration is the exception.
  Explicit on/off/status; no
  admin rights for normal operation, no task registration, no hook installation.
  Legacy cleanup may require elevation. Use when the user wants the PC not to sleep
  during long unattended runs. Triggers / 触发词: keep awake, prevent sleep, never sleep,
  stop windows sleeping, stay awake, don't let my computer sleep, 防休眠, 防止系统休眠,
  保持唤醒, 让电脑不休眠, 挂机不休眠, 别睡眠.
---

# keep-awake - keep a Windows 11 PC awake while AI agents work (Windows only)

`scripts/keep-awake.ps1` is the single entry point. State lives in `~/.keep-awake/`.

## What `on` actually does (the whole contract)

- Blocks **system idle sleep** via `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`,
  held by a hidden `awake-watcher.ps1` daemon. Nothing else is touched.
- **AC power only.** Unplug -> release on the next power poll (roughly within 5 seconds),
  then Windows' normal sleep timers apply. Plug back in -> it holds again. If the power state cannot be read, it holds
  nothing and says so (never fake).
- **The screen is allowed to turn off** (Windows display timeout). The daemon never sets
  ES_DISPLAY_REQUIRED. Other applications may still keep the display on.
- **Normal operation never changes lid close, the power button, or the power plan.**
  No task registration or hook installation. Legacy cleanup through `off` is the only
  exception: it may restore old power settings and request UAC for old task/backup/strong
  artifacts, and remove recognized old hooks from existing settings files.
- **Does not survive reboot.** After a reboot, run `on` again.

## Commands

| Intent | Command |
|---|---|
| Start protecting while a long task runs | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 on` |
| Stop / allow sleep again | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 off` |
| Report state | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/keep-awake.ps1 status` |

Use an absolute path to the script when calling from another directory.

Not installed yet? Run the agent one-liner from the README ("install in one line"):
`$env:KEEP_AWAKE_AGENT=1; irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex`
It prints `READY <dir>` and exits 0 on success; then call `<dir>\scripts\keep-awake.ps1`.

## Hard rules

- Run `on` when the user asks for no-sleep during a long unattended task; run `off` as
  soon as the task finishes. Never leave `on` dangling.
- On battery, `on` reports protection is idle - do not claim the PC will stay awake.
- Do not independently call `powercfg`, register tasks, or install hooks. Use `off` for
  legacy cleanup; report failures and preserve backups instead of deleting them manually.
- Check command exit codes and published state before claiming protection or cleanup.
  Unknown power or an API error is not success. `off` can return nonzero even after the
  daemon stops if legacy cleanup fails.
- This is one shared switch, not per-agent reference counting: `off` releases it for other
  tasks using the same state too. It does not override manual sleep, lid close, or power-button actions.
- The old modes and lid-protection features were removed on purpose (contract: 2026-10-14).

## Status line (optional)

- `scripts/statusline.ps1` prints a single line from state files plus a process-ownership
  check. It does not read stdin, write files, or change settings.
- For Claude Code only, manually merge a `statusLine` command into its settings; see
  [README.md](README.md#状态行可选) for a quoted-path example. Native pi settings do not
  use that field; the script may instead be run directly.
- See [QUICKSTART.md](QUICKSTART.md) for legacy cleanup, uninstall, and troubleshooting.

## Platform

Windows 11. The documented workflow requires PowerShell 7 (`pwsh`) on PATH; a 5.1-only
workflow is not guaranteed. Modern Standby behavior depends on OS/firmware. Non-Windows is unsupported.
