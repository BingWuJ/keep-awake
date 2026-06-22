#!/usr/bin/env pwsh
# awake-watcher.ps1 - Lever 1 daemon for keep-awake (Windows).
#
# Holds SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)
# for the lifetime of the process, re-asserting every 60s so the flag survives
# sleep/resume cycles (PowerToys issue #32544: ES_CONTINUOUS can be dropped after resume).
#
# Single-instance via a named Mutex. try/finally explicitly clears the flag on exit
# (we do not rely solely on process death - mirrors PowerToys Manager.CancelExistingThread).
#
# Invoked hidden/detached by keep-awake.ps1. Writes its own PID to awake.pid so the
# parent can manage it. Not intended to be run directly by users.
#
# Params:
#   -NoDisplay   keep the SYSTEM awake but allow the display to turn off
#                (ES_CONTINUOUS | ES_SYSTEM_REQUIRED). Default keeps the display on too.

[CmdletBinding()]
param(
    [switch]$NoDisplay
)

$ErrorActionPreference = 'Stop'

# ---- State dir ---------------------------------------------------------------
$StateDir = Join-Path $env:USERPROFILE '.keep-awake'
$PidFile  = Join-Path $StateDir 'awake.pid'
$StopFile = Join-Path $StateDir 'stop'      # sentinel: keep-awake.ps1 'off' creates this for graceful exit
$LogFile  = Join-Path $StateDir 'awake-watcher.log'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Write-Log {
    param([string]$Msg)
    $line = '{0} [PID {1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $Msg
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

# ---- P/Invoke: kernel32!SetThreadExecutionState ------------------------------
if (-not ('KeepAwake.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace KeepAwake {
    public static class Native {
        [FlagsAttribute]
        public enum EXECUTION_STATE : uint {
            ES_AWAYMODE_REQUIRED = 0x00000040,
            ES_CONTINUOUS        = 0x80000000,
            ES_SYSTEM_REQUIRED   = 0x00000001,
            ES_DISPLAY_REQUIRED  = 0x00000002
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);
    }
}
'@
}

# Compute the flag combination
$ES_CONT = [KeepAwake.Native+EXECUTION_STATE]::ES_CONTINUOUS
$ES_SYS  = [KeepAwake.Native+EXECUTION_STATE]::ES_SYSTEM_REQUIRED
$ES_DISP = [KeepAwake.Native+EXECUTION_STATE]::ES_DISPLAY_REQUIRED

if ($NoDisplay) {
    $AwakeState = $ES_CONT -bor $ES_SYS
} else {
    $AwakeState = $ES_CONT -bor $ES_SYS -bor $ES_DISP
}
$ClearState = $ES_CONT

# ---- Single-instance Mutex (non-blocking) ------------------------------------
$Mutex = $null
$Owned = $false
try {
    # Objective requires a system-wide named mutex to prevent duplicate daemons.
    $Mutex = New-Object System.Threading.Mutex($false, 'Global\keep-awake-watcher')
    try {
        # WaitOne(0): non-blocking. Returns true if acquired, false if another instance holds it.
        $Owned = $Mutex.WaitOne([int]0, $false)
    } catch [System.Threading.AbandonedMutexException] {
        # Previous holder crashed without releasing - we now own it.
        $Owned = $true
        Write-Log 'Recovered Global Mutex after previous instance crashed.'
    }
    if (-not $Owned) {
        Write-Log 'Another awake-watcher instance is already running. Exiting.'
        exit 0
    }
} catch {
    # UnauthorizedAccess etc. - continue best-effort without the single-instance guard;
    # it is better to provide protection than to bail.
    Write-Log "Global Mutex error (continuing without single-instance guard): $($_.Exception.Message)"
    $Mutex = $null
}

Write-Log ('Starting. State=0x{0:x8} NoDisplay={1}' -f [uint32]$AwakeState, $NoDisplay.IsPresent)

# Write our PID so the parent can track us
try {
    Set-Content -Path $PidFile -Value $PID -Encoding ASCII -ErrorAction Stop
} catch {
    Write-Log "Could not write PID file: $($_.Exception.Message)"
}

# ---- Assert + heartbeat loop -------------------------------------------------
# The loop sleeps in 5s ticks. Every tick it checks for a stop sentinel (graceful exit);
# every 60s it re-asserts the execution state so we survive sleep/resume cycles that
# drop the ES_CONTINUOUS flag (PowerToys #32544).
$TickSec     = 5
$ReassertSec = 60
try {
    $ret = [KeepAwake.Native]::SetThreadExecutionState($AwakeState)
    if ($ret -eq 0) {
        Write-Log 'ERROR: SetThreadExecutionState returned 0 (failed). State NOT held.'
    } else {
        Write-Log 'Initial state asserted OK.'
    }

    # Remove any stale stop sentinel from a previous run before entering the loop.
    Remove-Item -Path $StopFile -Force -ErrorAction SilentlyContinue

    $elapsed = 0
    while ($true) {
        Start-Sleep -Seconds $TickSec
        if (Test-Path -Path $StopFile) {
            Write-Log 'Stop sentinel detected. Exiting gracefully.'
            break
        }
        $elapsed += $TickSec
        if ($elapsed -ge $ReassertSec) {
            [void][KeepAwake.Native]::SetThreadExecutionState($AwakeState)
            $elapsed = 0
        }
    }
} finally {
    # Explicit cleanup - do not rely solely on process death to release the flag.
    [void][KeepAwake.Native]::SetThreadExecutionState($ClearState)
    Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
    Write-Log 'Stopped. Flag cleared.'
    if ($Owned -and $Mutex) { try { $Mutex.ReleaseMutex() } catch { } }
    if ($Mutex) { $Mutex.Dispose() }
}
