# keep-awake — keep your Mac awake (even with the lid closed)

[![platform: macOS](https://img.shields.io/badge/platform-macOS-black)](#requirements--compatibility)
[![shell + python](https://img.shields.io/badge/built%20with-bash%20%2B%20python-blue)](#requirements--compatibility)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Stop your Mac from sleeping while long tasks run** — keep the display on, prevent system sleep,
and optionally **stay awake even when the lid is closed** (clamshell), the external display is unplugged,
or you're on battery. A tiny, scriptable, open-source **caffeinate / Amphetamine / Caffeine-app alternative**
with a menu-bar control panel — built specifically so **AI agents and autonomous coding tools keep running
unattended**.

[« 简体中文](README.md) · **English**

---

## Why

When you kick off a long job — an **AI agent / Claude Code / Claude Code Connectors** run, a model download,
a render, a build, a data sync — and walk away, macOS dims the screen and goes to sleep, and your task stalls.
`keep-awake` holds the system awake for exactly as long as you need, then gets out of the way.

Built for the **"let the AI keep working while I'm away"** use case, with three intensity levels and a
**menu-bar indicator** so you can always see, at a glance, whether your Mac is being kept awake.

## Features

- 🔆 Prevent **display sleep**, **idle sleep**, **disk sleep**, and **system sleep**.
- 🛡️ Optional **"awake with the lid closed"** — keeps running clamshell, lid shut, external display unplugged, even on battery.
- 🎛️ **Three named modes** (super / flex / normal) for different needs.
- ⚡ **Flex auto-cycle**: awake *only while the agent is working*, auto-released when it stops (via Claude Code hooks). Saves battery.
- 🍫 **Menu-bar control panel**: see the current state in the top-right, switch modes / stop with one click.
- 🧩 **Optional Claude Code skill** (`SKILL.md`) — an AI agent can drive it by intent ("keep my Mac awake while you work").
- 🪶 Pure `bash` + system tools (`caffeinate`, `pmset`). No daemon you have to babysit; no kernel extension.

## The three modes

| Mode | What it does | Lid closed | Needs auth |
|------|--------------|------------|------------|
| **normal** | No display/idle sleep while the lid is open | sleeps | no |
| **flex** ⭐ | Awake **only while the agent works**; auto-released when it stops | awake *while working* | yes (for lid) |
| **super** | Never sleeps until you stop it — lid closed / unplugged / on battery | awake | yes (for lid) |

⭐ **flex** is the everyday recommendation: protection while you work, automatic power-saving when idle.

## Requirements & compatibility

- **macOS only.** This tool relies on `caffeinate` and `pmset`, which are macOS-specific. It does **not** work on Windows or Linux. (It exits with a clear message on non-Darwin systems.)
- Works on both **Apple Silicon** and **Intel** Macs.
- **Core CLI** (`scripts/keep-awake.sh`): needs nothing beyond macOS itself.
- **Menu-bar indicator**: needs **Python 3** + [`rumps`](https://pypi.org/project/rumps/) (the installer handles it).
- **"Awake with lid closed"**: needs a **one-time `sudo` authorization** (see below) because it toggles a system power setting (`pmset disablesleep`).
- **Flex auto-cycle** and the **status line** are **optional Claude Code integrations** (they use Claude Code hooks / `statusLine` in `~/.claude/settings.json`). Without Claude Code, super and normal modes work fully, and flex can be driven by any tool's hooks.
- ⚠️ **Notch MacBooks**: a menu-bar item can be hidden behind the notch when a focused app has a wide menu bar. The indicator title is kept short for this reason; you can also ⌘-drag it further right.

## Install

```bash
git clone https://github.com/aurthur/keep-awake.git
cd keep-awake
./install.sh
```

The installer sets up the menu-bar indicator (a `Sleep OK` item appears top-right) and registers a
LaunchAgent so it auto-starts at login. The core CLI works immediately with no install:

```bash
bash scripts/keep-awake.sh on flex
```

## Usage

### Command line

```bash
bash scripts/keep-awake.sh on normal     # awake with lid open (sleeps when closed)
bash scripts/keep-awake.sh on flex        # awake while working, auto-release when idle
bash scripts/keep-awake.sh on super       # never sleep (lid/unplug/battery) until 'off'
bash scripts/keep-awake.sh status         # show current state
bash scripts/keep-awake.sh off            # stop everything, restore normal sleep
bash scripts/keep-awake.sh off --sleep-now  # stop and sleep immediately
```

### Menu bar

After `./install.sh`, click the top-right indicator to switch modes or stop — the current mode is checkmarked.

### Claude Code skill

Drop the folder into `~/.claude/skills/keep-awake/` (or symlink it). An agent can then keep the Mac awake by
intent. `SKILL.md` documents the trigger phrases and workflow. `on flex` also installs Claude Code hooks
(`UserPromptSubmit → arm`, `Stop → disarm`) so protection follows your work automatically.

## "Awake with lid closed" — one-time authorization

The lid-proof feature flips a system setting (`pmset disablesleep`), which needs root. To avoid typing your
password every time, you grant a **narrow, passwordless `sudoers` rule** once. Run `on super` (or `on flex`)
and it prints the exact command, or run it yourself:

```bash
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" \
  | sudo tee /etc/sudoers.d/keep-awake >/dev/null \
  && sudo chmod 440 /etc/sudoers.d/keep-awake \
  && sudo visudo -cf /etc/sudoers.d/keep-awake && echo OK
```

**Security note:** this whitelists *only* toggling `pmset disablesleep` (on/off) without a password — nothing
else. Revoke any time with `sudo rm /etc/sudoers.d/keep-awake`. `off` always resets `disablesleep` to `0`, so
you never get stuck awake.

⚠️ With the lid closed and no external display, a Mac under sustained load runs hot, and it never sleeps on
battery — run `off` when you're done.

## How it works

Two system "levers":

1. **`caffeinate -dims`** — blocks display, idle, disk, and system sleep. No privileges. *Can't* block lid-close sleep.
2. **`pmset disablesleep`** — blocks *all* sleep, including lid-close / on-battery. Needs root (the one-time auth above).

The three modes are just different combinations: `normal` = lever 1; `super` = levers 1 + 2 always on;
`flex` = levers 1 + 2 only while the agent is working (toggled by Claude Code hooks). State lives in
`~/.keep-awake/`; the menu-bar app reads it every 3 seconds and is kept alive by `launchd`.

## Uninstall

```bash
./uninstall.sh
# then, to revoke the lid-proof authorization:
sudo rm /etc/sudoers.d/keep-awake
```

## Keywords

keep mac awake · prevent sleep mac · stop mac from sleeping · disable sleep macOS · keep display on ·
prevent display sleep · no sleep · never sleep · stay awake · insomnia for mac · keep awake with lid closed ·
clamshell mode lid closed · closed-display mode · keep mac running with lid down · prevent sleep on battery ·
`caffeinate` GUI · `pmset disablesleep` · Amphetamine alternative · Caffeine app alternative · KeepingYouAwake
alternative · NoSleep · Lungo · Owly · menu bar caffeine · keep awake while AI agent runs · keep mac awake for
Claude Code · Claude Code Connectors stay awake · autonomous agent keep computer awake · long task no sleep ·
防休眠 · 防止系统休眠 · 合盖不休眠 · 保持清醒 · 显示屏常亮 · 让电脑不休眠 · 挂机不休眠

## License

[MIT](LICENSE)
