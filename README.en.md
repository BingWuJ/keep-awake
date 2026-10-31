# keep-awake

**Don't let Windows 11 fall asleep in the middle of a long run.**

On AC power it blocks system idle sleep so AI agents and batch jobs finish; unplug and it lets go immediately, and the screen still turns off on its own schedule. One PowerShell script: no admin, no scheduled task, no power-plan changes.

[![Platform: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#platform)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#platform)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Install in one line

**For humans** — paste into a PowerShell 7 window:

```powershell
irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\keep-awake`, syntax-checks the scripts, scans for leftovers of the old design, and prints the commands you need. No admin, no registry writes, no PATH edits.

**For agents** — hand this to an agent, or let it run it:

```powershell
$env:KEEP_AWAKE_AGENT=1; irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex
# success prints exactly one line: READY C:\Users\<you>\AppData\Local\Programs\keep-awake
```

Agent mode is non-interactive with no colour and no prompts; `READY` plus exit code 0 is the only success signal. Call it by absolute path afterwards:

```powershell
& "$env:LOCALAPPDATA\Programs\keep-awake\scripts\keep-awake.ps1" on
```

> `irm | iex` downloads and runs. To review first: `irm <same URL> -OutFile setup.ps1`, read it, then `.\setup.ps1`.
> Install elsewhere with `-Dir <path>`, or just `git clone` and run `.\install.ps1`.

## Three commands

```powershell
$k = "$env:LOCALAPPDATA\Programs\keep-awake\scripts\keep-awake.ps1"
pwsh -NoProfile -File $k on      # block system idle sleep while on AC
pwsh -NoProfile -File $k status  # power source, screen policy, daemon state
pwsh -NoProfile -File $k off     # stop, back to normal sleep
```

## What it does

- 🔌 **Blocks system idle sleep on AC power** (`SetThreadExecutionState`), so downloads, renders, and agent runs are not cut off mid-way.
- 🪫 **Releases on unplug** at the next power poll (roughly 5 seconds); Windows' normal sleep timers take over, and plugging back in holds again.
- ❓ **Holds nothing when the power state cannot be read** — and says so. It never fakes being awake.
- 🖥️ **Lets the screen turn off** on the Windows display timeout; never touches the display idle timer.

## What it does not do

- ❌ No forced display-on.
- ❌ No changes to lid close, the power button, or the power plan; normal operation never calls `powercfg`.
- ❌ No admin rights, no scheduled tasks, no UAC prompts, no hooks.
- ❌ Does not survive a reboot — run `on` again.
- ❌ Does not override manual sleep, and does not guarantee uninterrupted execution under Modern Standby.

> These trade-offs come from a decision-by-decision grilling of the old design (super/flex
> modes + a highest-privilege scheduled task + lid-close protection). Conclusion: the lid
> and forced-display features were not worth a persistent admin entry point. All removed.

## Wiring it into an agent

As a pi / Claude Code skill: put the install directory on the skill path (or symlink it).
`SKILL.md` tells the agent to run `on` when a long unattended task starts and `off` when it ends.
Running the commands by hand works just as well.

This is a **shared switch**, not per-agent reference counting: `off` releases it for every task
using the same state.

## How it works

One lever plus power monitoring, all without elevation:

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`** — held by the hidden
   `awake-watcher.ps1` daemon; blocks system idle sleep only. Re-asserted every 60s and the
   power source is polled every 5s: unplug → release, replug → hold again, unknown → release and mark.
2. **Transparent state** — the daemon publishes `watcher-state` under
   `%USERPROFILE%\.keep-awake\`. The CLI and status line read it and verify process ownership.
   `status` also reads the power source and queries legacy tasks.

The new design never sets `ES_DISPLAY_REQUIRED`, registers tasks, or installs hooks.
Restoring/removing legacy artifacts is the only power-plan and existing-hook exception.
Manual sleep, lid close, and the power button still follow Windows settings. Actual Modern
Standby power behavior depends on the OS and firmware.

## Self-check (optional)

```powershell
.\install.ps1
```

Does exactly two things: syntax-checks the core scripts and detects leftovers of the old
design. Registers nothing.

## Status line (optional)

This optional manual example is for **Claude Code only**, not written by this tool.
Merge it into `~/.claude/settings.json` without replacing existing settings; use your actual
install path and keep quotes for paths containing spaces (see the [official docs](https://code.claude.com/docs/en/statusline)).
Native pi settings do not have this `statusLine` field; do not copy the example into pi.

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"C:/Users/<you>/AppData/Local/Programs/keep-awake/scripts/statusline.ps1\""
  }
}
```

Shows `● Awake (AC)` / `◐ Awake idle (battery - not held)` / `⚠` error or stale state / `○ Sleep OK`.
Run it directly with `pwsh -NoProfile -File .\scripts\statusline.ps1`.

## Upgrading from the old version

The old version (super/flex) modified the power plan through a highest-privilege scheduled
task. The new `off` or `uninstall.ps1` cleans that up in one pass:

- restores the power plan from its backup;
- deletes the `keep-awake-strong` and `keep-awake-bootcheck` scheduled tasks; legacy tasks,
  backups, or strong files may trigger one elevation request;
- removes recognized keep-awake `arm`/`disarm` hooks from existing pi / Claude Code settings.
  Hook-only cleanup does not require UAC.

A corrupt backup, failed restore, or cancelled UAC causes `off` / uninstall to return nonzero
and preserve legacy artifacts. Address the error before retrying; do not delete the backup.

## Uninstall

```powershell
pwsh -NoProfile -File "$env:LOCALAPPDATA\Programs\keep-awake\uninstall.ps1"
```

Stops the daemon, cleans legacy leftovers, verifies old tasks are gone, then removes
`%USERPROFILE%\.keep-awake\`. A missing core script, failed `off`, remaining task, or failed
directory deletion returns nonzero without claiming success. The program folder itself is left
in place; delete it yourself if you want it gone. A manually configured `statusLine` is not
removed either.

## Platform

- Windows 11 only (including S0 Modern Standby devices).
- Requires PowerShell 7 (`pwsh`) on PATH. A Windows PowerShell 5.1-only setup is not supported.
- Non-Windows systems are unsupported.

## Keywords

keep windows awake · prevent sleep · stop windows sleeping · stay awake · unattended ·
AI agent · SetThreadExecutionState · no admin · no scheduled task · Windows 11 · PowerShell

## License

[MIT](LICENSE)
