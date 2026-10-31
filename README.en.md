# keep-awake

**Don't let Windows 11 fall asleep in the middle of a long run.**

On AC power it blocks system idle sleep so AI agents and batch jobs finish; unplug and it lets go immediately, and the screen still turns off on its own schedule. One PowerShell script: no admin, no scheduled task, no power-plan changes.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on
```

[![Platform: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#platform)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#platform)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Why you need it

An agent is halfway through a job, the idle timer fires, the machine sleeps, and you come back to half a result and a dead terminal. The usual workaround is setting the display timeout to "Never" and leaving the monitor lit all night.

keep-awake does one thing: **while plugged in, it tells Windows "don't sleep because you're idle."** The screen turns off whenever it normally would — no extra power draw, no burn-in.

## What it does

- 🔌 **Blocks system idle sleep on AC power** (`SetThreadExecutionState`), so downloads, renders, and agent runs are not cut off mid-way.
- 🪫 **Releases on unplug** at the next power poll (roughly within 5 seconds); Windows' normal sleep timers take over. Plug back in and it holds again.
- ❓ **Holds nothing when the power state cannot be read** — and says so. It never fakes being awake.
- 🖥️ **Lets the screen turn off** on the Windows display timeout; it never touches the display idle timer.

## What it does not do

- ❌ No forced display-on.
- ❌ No changes to lid close, the power button, or the power plan; normal operation never calls `powercfg`.
- ❌ No admin rights, no scheduled tasks, no UAC prompts, no hooks.
- ❌ Does not survive a reboot — run `on` again.
- ❌ Does not override manual sleep, and does not guarantee uninterrupted execution under Modern Standby.

> These trade-offs come from a decision-by-decision grilling of the old design (super/flex
> modes + a highest-privilege scheduled task + lid-close protection). Conclusion: the lid
> and forced-display features were not worth a persistent admin entry point. All removed.

## Three commands

No installation, no admin required:

```powershell
# Start: blocks system idle sleep while on AC (on battery it holds nothing and says so)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on

# Status: current state (power source, screen policy, legacy leftovers)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status

# Stop: back to normal sleep behavior
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off
```

`status` verifies daemon process ownership and detects legacy leftovers. The status line writes no files and does not read stdin.

## Wiring it into an agent

As a pi / Claude Code skill: place this repo in the skill path (or symlink it). `SKILL.md`
tells the agent to run `on` when a long unattended task starts and `off` when it ends. Running
the commands by hand works just as well without an agent.

This is a **shared switch**, not per-agent reference counting: `off` releases it for every task
using the same state.

## How it works

One lever plus power monitoring, all without elevation:

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`** — held by the hidden
   `awake-watcher.ps1` daemon; blocks system idle sleep only. Re-asserted every 60s
   (guards against the flag being dropped after sleep/resume) and the power source is
   polled every 5s: unplug → release, replug → hold again, unknown → release and mark.
2. **Transparent state** — the daemon publishes `watcher-state` under
   `%USERPROFILE%\.keep-awake\`. The CLI and status line read it and verify process ownership.
   `status` also reads the power source and queries legacy tasks; the CLI creates its state
   directory if absent.

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

## Keywords

keep windows awake · prevent sleep · stop windows sleeping · stay awake · unattended ·
AI agent · SetThreadExecutionState · no admin · no scheduled task · Windows 11 · PowerShell

## License

[MIT](LICENSE)
