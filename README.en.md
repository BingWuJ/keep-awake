# keep-awake — keep Windows 11 awake during long tasks

[![Platform: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#platform)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#platform)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**While plugged in, requests prevention of system idle sleep during long tasks and lets the screen turn off. Normal operation leaves lid, power-button, and power-plan settings unchanged; legacy restoration is the only exception.**
A pure-PowerShell Windows anti-sleep tool built for unattended AI agents and long runs.

---

## What it does / does not do (honest list)

**Does:**

- 🔌 While **on AC power**, requests prevention of system idle sleep (`SetThreadExecutionState`) for downloads, renders, and AI agent runs. It does not override manual sleep or OS/firmware restrictions.
- 🪫 **Unplug → releases on the next power poll** (roughly within 5 seconds). Windows' normal sleep timers take over; plug back in and it holds again. It never holds on battery.
- ❓ If the power state cannot be read: **holds nothing and says so.** Never fakes.
- 🖥️ It does not prevent the Windows **display timeout** from turning off the screen. Other applications may still affect that timeout.

**Does not:**

- ❌ No power plan changes or `powercfg` calls during normal operation; restoring an old version's backup is the only exception.
- ❌ No admin rights or UAC during normal operation, and no task registration. Legacy task/backup/strong-file cleanup may request elevation.
- ❌ No forced display-on; never touches the display idle timer.
- ❌ Normal operation does not change lid-close or power-button behavior; legacy restoration may restore an old lid setting.
- ❌ Never installs hooks or creates pi / Claude Code `settings.json`. `off` may remove recognized old keep-awake hooks from existing settings files.
- ❌ Does not survive a reboot — run `on` again.

> These trade-offs come from a decision-by-decision grilling of the old design (super/flex
> modes + a highest-privilege scheduled task + lid-close protection). Conclusion: the lid
> and forced-display features were not worth a persistent admin entry point. All removed.

## Usage

No installation, no admin required:

```powershell
# Start: blocks system idle sleep while on AC (on battery it holds nothing and says so)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on

# Status: current state (power source, screen policy, legacy leftovers)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status

# Stop: back to normal sleep behavior
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off
```

As a pi / Claude Code skill: place this repo in the skill path (or symlink it). `SKILL.md`
tells the agent to run `on` when a long unattended task starts and `off` when it ends.

## How it works

One lever plus power monitoring, all without elevation:

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`** — held by the hidden
   `awake-watcher.ps1` daemon; blocks system idle sleep only. Re-asserted every 60s
   (guards against the flag being dropped after sleep/resume) and the power source is
   polled every 5s: unplug → release, replug → hold again, unknown → release and mark.
2. **Transparent state** — the daemon publishes `watcher-state` under
   `%USERPROFILE%\.keep-awake\`. The CLI and status line read it and verify process ownership.
   `status` also reads the power source and queries legacy tasks; the CLI creates its state
   directory if absent. The status line writes no files and does not read stdin.

The new design never sets `ES_DISPLAY_REQUIRED`, registers tasks, or installs hooks.
Restoring/removing legacy artifacts is the only power-plan and existing-hook exception.
Manual sleep, lid close, and the power button still follow Windows settings. Actual Modern
Standby power behavior depends on the OS and firmware; uninterrupted execution is not guaranteed.

## Install (optional)

```powershell
.\install.ps1
```

Does exactly two things: syntax-checks the core scripts and detects leftovers of the old
design. Registers nothing.

## Status line (optional)

This optional manual example is for **Claude Code only**, not written by this tool.
Merge it into `~/.claude/settings.json` without replacing existing settings. Use your actual
repo path and keep quotes for paths containing spaces; see the [official documentation](https://code.claude.com/docs/en/statusline).
Native pi settings do not have this `statusLine` field; do not copy the example into pi.

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"E:/keep-awake/scripts/statusline.ps1\""
  }
}
```

Shows `● Awake (AC)` / `◐ Awake idle (battery - not held)` / `⚠` error or stale state / `○ Sleep OK`.
It can also be run directly: `pwsh -NoProfile -File .\scripts\statusline.ps1`.

## Upgrading from the old version

The old version (super/flex) modified the power plan through a highest-privilege scheduled
task. The new `off` or `uninstall.ps1` cleans that up in one pass:

- restores the power plan from its backup;
- deletes the `keep-awake-strong` and `keep-awake-bootcheck` scheduled tasks; legacy tasks,
  backups, or strong files may trigger one elevation request;
- removes recognized keep-awake `arm`/`disarm` hooks from existing pi / Claude Code settings.
  Hook-only cleanup does not require UAC.

A corrupt backup, failed restore, or cancelled UAC causes `off` / uninstall to return nonzero
and preserve legacy artifacts. Address the error before retrying; do not simply delete the backup.

## Uninstall

```powershell
.\uninstall.ps1
```

Stops the daemon, cleans legacy leftovers, verifies old tasks are gone, then removes
`%USERPROFILE%\.keep-awake\`. A missing core script, failed `off`, remaining task, or failed
directory deletion returns nonzero without claiming success. Fix the error and retry.
A manually configured `statusLine` is not removed; remove or merge it yourself.

## Platform

- Windows 11 only (including S0 Modern Standby devices).
- Commands in this guide and the install/uninstall scripts require PowerShell 7 (`pwsh`)
  on PATH. The complete workflow is not guaranteed in a Windows PowerShell 5.1-only environment.
- Non-Windows systems are unsupported.

## License

[MIT](LICENSE)
