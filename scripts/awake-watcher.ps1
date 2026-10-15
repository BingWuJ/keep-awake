#!/usr/bin/env pwsh
# awake-watcher.ps1 - The only daemon of keep-awake (Windows).
#
# Holds SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) while the machine is
# on AC power, re-asserting every 60s (the flag can be dropped after sleep/resume;
# PowerToys issue #32544). It never sets ES_DISPLAY_REQUIRED: the screen follows the
# Windows display timeout and may go black on its own. It never touches powercfg, lid
# actions, or anything that needs elevation.
#
# Contract (settled in the 2026-06 grilling session):
#   AC online  -> hold the system awake.
#   AC offline -> release at once; Windows normal sleep timers apply (battery never held).
#   replug     -> hold again while the session is still open.
#   unknown    -> release, mark error, never fake.
#
# Single instance via a Global\ mutex plus a pid file. Exits within ~5s once the stop
# sentinel (~/.keep-awake/stop) appears. Publishes its state to watcher-state for
# keep-awake.ps1 status and statusline.ps1. Not intended to be run directly by users.

$ErrorActionPreference = 'Stop'

# ---- State dir ---------------------------------------------------------------
$StateDir = Join-Path $env:USERPROFILE '.keep-awake'
$PidFile  = Join-Path $StateDir 'awake.pid'
$StopFile = Join-Path $StateDir 'stop'            # sentinel: keep-awake.ps1 off creates this
$StateOut = Join-Path $StateDir 'watcher-state'   # holding-ac | released-battery | error-power-unknown | stopped
$LogFile  = Join-Path $StateDir 'awake-watcher.log'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Write-Log {
    param([string]$Msg)
    # Keep the log bounded: restart it if it grows past 256 KB.
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 256KB)) {
        Set-Content -Path $LogFile -Value ('{0} [PID {1}] log rotated' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID) -Encoding UTF8
    }
    $line = '{0} [PID {1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $Msg
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Set-PublishedState {
    param([string]$S)
    # Honest publishing: report failure to the caller instead of swallowing it -
    # a swallowed failure leaves a stale terminal state (e.g. holding-ac after release).
    try {
        Set-Content -Path $StateOut -Value $S -Encoding ASCII -ErrorAction Stop
        return $true
    } catch {
        Write-Log "failed to publish state '$S': $($_.Exception.Message)"
        return $false
    }
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

$ES_CONT = [KeepAwake.Native+EXECUTION_STATE]::ES_CONTINUOUS
$ES_SYS  = [KeepAwake.Native+EXECUTION_STATE]::ES_SYSTEM_REQUIRED
# Deliberately NO ES_DISPLAY_REQUIRED: the screen is allowed to turn off (settled contract).
$HoldState  = $ES_CONT -bor $ES_SYS
$ClearState = $ES_CONT

# ---- Power source ------------------------------------------------------------
function Get-PowerLine {
    # Online / Offline / Unknown. Unknown must never be treated as "keep awake".
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return [string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
    } catch {
        Write-Log "PowerStatus unavailable: $($_.Exception.Message)"
        return 'Unknown'
    }
}

# ---- Main loop with single-instance mutex ------------------------------------
$Mutex = $null
$Owned = $false
try {
    $Mutex = New-Object System.Threading.Mutex($false, 'Global\keep-awake-watcher')
    # ONLY an abandoned mutex (previous holder killed) is safe to take over.
    # Any other exception proves nothing about ownership - fail closed, do not
    # touch the pid file, do not run the protected main loop.
    try {
        $Owned = $Mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $Owned = $true
    }
    if (-not $Owned) {
        Write-Log 'another watcher already holds the mutex - exiting'
        return
    }

    Set-Content -Path $PidFile -Value $PID -Encoding ASCII
    # Publish a transitional state immediately so the parent can never mistake a stale
    # state file (left by a previous run) for this daemon's real state.
    Set-PublishedState 'starting'
    Write-Log "watcher started (hold only on AC; screen not forced)"

    $PollSeconds     = 5
    $ReassertSeconds = 60
    # Honest model of the thread's ES flag: Held = confirmed held; NotHeld = confirmed
    # cleared (or never held); Uncertain = an API/clear failed - the flag MAY still be
    # set. While Uncertain we never claim holding-ac or released-battery.
    $FlagState  = 'NotHeld'
    $LastAssert = [datetime]::MinValue
    $Published  = 'starting'   # last state successfully written to disk

    while ($true) {
        if (Test-Path $StopFile) {
            Write-Log 'stop sentinel seen - exiting'
            break
        }
        $pl = Get-PowerLine
        $desired = ''
        if ($pl -eq 'Online') {
            if ($FlagState -ne 'Held' -or ((Get-Date) - $LastAssert).TotalSeconds -ge $ReassertSeconds) {
                $prev = [KeepAwake.Native]::SetThreadExecutionState($HoldState)
                if ($prev -ne [KeepAwake.Native+EXECUTION_STATE]0) {
                    $FlagState = 'Held'
                    $LastAssert = Get-Date
                    $desired = 'holding-ac'
                } else {
                    # A failed call does NOT prove an old flag is gone: clear
                    # explicitly, and only drop to NotHeld on a CONFIRMED clear.
                    if ($FlagState -ne 'NotHeld') {
                        $clr = [KeepAwake.Native]::SetThreadExecutionState($ClearState)
                        if ($clr -ne [KeepAwake.Native+EXECUTION_STATE]0) {
                            $FlagState = 'NotHeld'
                            Write-Log 'assert failed; old flag explicitly cleared'
                        } else {
                            $FlagState = 'Uncertain'
                            Write-Log 'assert failed AND clear failed - flag may still be held'
                        }
                    }
                    Write-Log 'SetThreadExecutionState returned 0 - not holding'
                    $desired = 'error-power-unknown'
                }
            } else {
                $desired = 'holding-ac'   # holding steadily, inside reassert window
            }
        } elseif ($pl -eq 'Offline') {
            if ($FlagState -ne 'NotHeld') {
                $clr = [KeepAwake.Native]::SetThreadExecutionState($ClearState)
                if ($clr -ne [KeepAwake.Native+EXECUTION_STATE]0) {
                    $FlagState = 'NotHeld'
                    Write-Log 'AC lost - released; Windows sleep timers apply'
                } else {
                    # Release failed: flag may still be held. NEVER claim released.
                    $FlagState = 'Uncertain'
                    Write-Log 'AC lost but clear FAILED - will retry next round'
                }
            }
            if ($FlagState -eq 'NotHeld') { $desired = 'released-battery' }
            else { $desired = 'error-power-unknown' }
        } else {
            if ($FlagState -ne 'NotHeld') {
                $clr = [KeepAwake.Native]::SetThreadExecutionState($ClearState)
                if ($clr -ne [KeepAwake.Native+EXECUTION_STATE]0) {
                    $FlagState = 'NotHeld'
                    Write-Log 'power status unknown - released (never fake)'
                } else {
                    $FlagState = 'Uncertain'
                    Write-Log 'power unknown and clear FAILED - will retry next round'
                }
            }
            $desired = 'error-power-unknown'
        }
        # Publish convergence: write whenever the desired state differs from the last
        # state that was SUCCESSFULLY written. A failed publish retries every loop (5s)
        # until it sticks, so a write failure can never leave a stale terminal state.
        if ($desired -ne $Published) {
            if (Set-PublishedState $desired) { $Published = $desired }
        }
        Start-Sleep -Seconds $PollSeconds
    }
} finally {
    if ($Owned) {
        # Explicitly clear the flag; do not rely on process death alone. Report an
        # uncertain final clear instead of silently claiming everything is clean.
        $clr = [KeepAwake.Native]::SetThreadExecutionState($ClearState)
        if ($clr -eq [KeepAwake.Native+EXECUTION_STATE]0) {
            Write-Log 'final clear FAILED - flag may persist after exit'
        }
        Set-PublishedState 'stopped'
        Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
        if ($Mutex) { $Mutex.ReleaseMutex() | Out-Null; $Mutex.Dispose() }
        Write-Log 'watcher stopped, execution state cleared'
    } else {
        if ($Mutex) { $Mutex.Dispose() }
    }
}
