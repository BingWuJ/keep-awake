#!/usr/bin/env pwsh
# statusline.ps1 - Optional status-line provider for pi / Claude Code.
#
# Wire via settings.json:
#   { "statusLine": { "type": "command", "command": "pwsh -NoProfile -File <path>\statusline.ps1" } }
#
# Prints one line with the current keep-awake state. Fast and never errors:
# any failure falls back to a default line so the status bar keeps rendering.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $StateDir = Join-Path $env:USERPROFILE '.keep-awake'
    $ModeFile = Join-Path $StateDir 'mode'
    $PidFile  = Join-Path $StateDir 'awake.pid'

    $mode = ''
    if (Test-Path $ModeFile) { $mode = (Get-Content $ModeFile -Raw -ErrorAction SilentlyContinue).Trim() }

    $strongActive = Test-Path (Join-Path $StateDir 'strong')

    $running = $false
    if (Test-Path $PidFile) {
        $pidVal = (Get-Content $PidFile -Raw -ErrorAction SilentlyContinue).Trim()
        $id = 0
        if ([int]::TryParse($pidVal, [ref]$id)) {
            try {
                $null = Get-Process -Id $id -ErrorAction Stop
                # Guard against recycled PID: verify it's actually our watcher script.
                $cmd = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop).CommandLine } catch { '' }
                if ($cmd -like '*awake-watcher.ps1*') { $running = $true }
            } catch { }
        }
    }

    $state = switch ($mode) {
        'super'  { '● Awake (Super)' }
        'flex'   { if ($running -or $strongActive) { '● Awake (Flex)' } else { '○ Flex idle' } }
        'normal' { if ($running) { '● Awake (Normal)' } else { '○ Sleep OK' } }
        default  { if ($strongActive) { '● Awake (residual)' } else { '○ Sleep OK' } }
    }
    [Console]::Out.WriteLine($state)
} catch {
    [Console]::Out.WriteLine('○ Sleep OK')
}
