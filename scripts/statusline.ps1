#!/usr/bin/env pwsh
# statusline.ps1 - 单行状态输出，可手动接入 Claude Code statusLine。
#
# 读取状态文件并通过 CIM 核实进程归属；不读 stdin、不提权、不写文件。
# pi 原生 settings 没有 Claude Code 的 statusLine 字段。
# The liveness check mirrors Test-WatcherRunning in keep-awake.ps1 (fail closed:
# a recycled pid that is not our watcher counts as dead) and every branch outputs
# exactly one line, so an unreadable state can never masquerade as "Awake".
#
# 手动合并到 Claude Code settings.json（不是 pi settings）：
#   {"statusLine": {"type": "command", "command": "pwsh -NoProfile -File <repo>\\scripts\\statusline.ps1"}}

$ErrorActionPreference = 'SilentlyContinue'

$StateDir = Join-Path $env:USERPROFILE '.keep-awake'
$ModeFile = Join-Path $StateDir 'mode'
$PidFile  = Join-Path $StateDir 'awake.pid'
$StateOut = Join-Path $StateDir 'watcher-state'

function Read-TextFile {
    # Zero-byte files yield $null from -Raw; normalize to '' (never crash, never lie).
    param([string]$Path)
    $raw = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ($null -ne $raw) { return $raw.Trim() }
    return ''
}

$mode = ''
if (Test-Path $ModeFile) { $mode = Read-TextFile $ModeFile }

if ($mode -ne 'on') {
    Write-Output '○ Sleep OK'
    exit 0
}

# Daemon alive check: pid parses, process lives, and its command line is OUR watcher.
$running = $false
if (Test-Path $PidFile) {
    $id = 0
    if ([int]::TryParse((Read-TextFile $PidFile), [ref]$id)) {
        $cmd = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop).CommandLine } catch { '' }
        if ($cmd -like '*awake-watcher.ps1*') { $running = $true }
    }
}
if (-not $running) {
    Write-Output '⚠ keep-awake stale (on, daemon dead)'
    exit 0
}

$st = ''
if (Test-Path $StateOut) { $st = Read-TextFile $StateOut }
switch ($st) {
    'holding-ac'          { Write-Output '● Awake (AC)' }
    'released-battery'    { Write-Output '◐ Awake idle (battery - not held)' }
    'error-power-unknown' { Write-Output '⚠ Awake error (power unknown - not held)' }
    default               { Write-Output "⚠ keep-awake (state: $st)" }   # empty/starting/unknown: never bare Awake
}
