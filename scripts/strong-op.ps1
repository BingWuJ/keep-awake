#!/usr/bin/env pwsh
# strong-op.ps1 - Lever 2 for keep-awake (Windows).
#
# Backs up the current power-plan values, then sets standby/hibernate timeouts to 0
# (and LidCloseAction to 0 "Do nothing" where the setting exists) - and restores them
# on 'off'. Runs ELEVATED (via the keep-awake-strong scheduled task), so keep-awake.ps1
# never needs a UAC prompt after the one-time install-task.
#
# Reads its orders from a tiny command file (~/.keep-awake/strong-cmd, JSON
# {"op":"on"|"off"|"restore","id":"<guid>"}) rather than argv, because schtasks /tr argument
# quoting on Windows is
# notoriously fragile. Writes results to ~/.keep-awake/strong-result.json.
#
# Idempotent: running 'on' twice re-backs-up from the CURRENT (already-modified) state
# only if the backup file is missing; otherwise the original backup is preserved.
# Running 'off'/'restore' without a backup is a no-op that logs a warning.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- Paths -------------------------------------------------------------------
$StateDir   = Join-Path $env:USERPROFILE '.keep-awake'
$CmdFile    = Join-Path $StateDir 'strong-cmd'
$BackupFile = Join-Path $StateDir 'power-backup.json'
$ResultFile = Join-Path $StateDir 'strong-result.json'
$StrongFlag = Join-Path $StateDir 'strong'
$LogFile    = Join-Path $StateDir 'strong-op.log'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Write-Log {
    param([string]$Msg, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
}

# Request id echo: keep-awake.ps1's Invoke-StrongOp tags each request with a GUID and
# only accepts a result whose id matches, so racing/stale task instances can't fool it.
# We stamp the id here from $script:reqId (set at entry from the command file).
function Write-Result {
    param([string]$Op, [string]$Status, [string]$Msg, [hashtable]$Extra = @{})
    $r = [ordered]@{
        op = $Op; status = $Status; msg = $Msg
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    if ($script:reqId) { $r['id'] = $script:reqId }
    foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }
    $r | ConvertTo-Json -Depth 6 | Set-Content -Path $ResultFile -Encoding UTF8
}

# ---- Power-plan settings we manage -------------------------------------------
# Each entry: alias -> @{ Sub = subgroup GUID; Set = setting GUID; Name = friendly }
# LidCloseAction is OPTIONAL: many S0-modern-standby machines have no such setting.
# We probe each setting before touching it.
$Settings = [ordered]@{
    LIDACTION     = @{ Sub = '4f971e89-eebd-4455-a8de-9e59040e7347'; Set = '5ca83367-6e45-459f-a27b-476b1d01c936'; Name = 'Lid close action' }
    STANDBYIDLE   = @{ Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; Name = 'Sleep after' }
    HIBERNATEIDLE = @{ Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '9d7815a6-7ee4-497e-8888-515a05f02364'; Name = 'Hibernate after' }
    UNATTENDSLEEP = @{ Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '7bc4f55f-8a8f-4ac3-8441-6c5b2f4a2c5a'; Name = 'System unattended sleep timeout' }
}

# Windows default fallback if the backup is unreadable. Timeouts in seconds.
# (Power plan defaults: standby 1800s AC / 600s DC; hibernate 0 / 0; unattended 120 / 60.)
$Defaults = @{
    # Windows default for lid close action is "Sleep" (1), not "Do nothing" (0).
    LIDACTION     = @{ AC = 1; DC = 1 }
    STANDBYIDLE   = @{ AC = 1800; DC = 600 }
    HIBERNATEIDLE = @{ AC = 0; DC = 0 }
    UNATTENDSLEEP = @{ AC = 120; DC = 60 }
}

# ---- Helpers -----------------------------------------------------------------
function Get-ActiveSchemeGuid {
    $oldEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = ''
    try {
        $out = powercfg /getactivescheme 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "powercfg /getactivescheme failed (exit $LASTEXITCODE). Output: $out" }
    } finally {
        $ErrorActionPreference = $oldEa
    }
    if ($out -match 'GUID:\s*([0-9a-fA-F-]{36})') { return $Matches[1].ToLower() }
    throw "Could not determine active power scheme GUID. Output: $out"
}

# Read AC/DC value of a setting. Returns $null if the setting does not exist on this machine.
# Tries a language-aware regex first (Chinese/English), then falls back to the
# last two 8-digit hex values in the output - powercfg prints the current AC/DC
# index lines near the end, while earlier hex values are min/max/increment.
function Get-SettingValue {
    param([string]$SubGuid, [string]$SetGuid)
    $oldEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = ''
    try {
        $out = powercfg /query SCHEME_CURRENT $SubGuid $SetGuid 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $oldEa
    }

    # Language-aware match.
    $ac = $null; $dc = $null
    if ($out -match '(?im)^\s*(?:当前交流电源设置索引|Current AC power setting index)[:：]\s*(0x[0-9a-fA-F]+|\d+)') {
        $ac = [Convert]::ToInt32(($Matches[1] -replace '^0x', ''), 16)
    }
    if ($out -match '(?im)^\s*(?:当前直流电源设置索引|Current DC power setting index)[:：]\s*(0x[0-9a-fA-F]+|\d+)') {
        $dc = [Convert]::ToInt32(($Matches[1] -replace '^0x', ''), 16)
    }
    if ($null -ne $ac -and $null -ne $dc) {
        return @{ AC = $ac; DC = $dc }
    }

    # Fallback: take the last two 8-digit hex values as AC/DC.
    $hexMatches = [regex]::Matches($out, '0x([0-9a-fA-F]{8})')
    if ($hexMatches.Count -ge 2) {
        $ac = [Convert]::ToInt32($hexMatches[$hexMatches.Count - 2].Groups[1].Value, 16)
        $dc = [Convert]::ToInt32($hexMatches[$hexMatches.Count - 1].Groups[1].Value, 16)
        return @{ AC = $ac; DC = $dc }
    }
    return $null
}

function Set-SettingValue {
    param([string]$SubGuid, [string]$SetGuid, [int]$AcValue, [int]$DcValue)
    $oldEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # /setacvalueindex SCHEME SUB SET value, then /setactive to commit.
        [void](powercfg /setacvalueindex SCHEME_CURRENT $SubGuid $SetGuid $AcValue 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "powercfg /setacvalueindex failed for $SetGuid (exit $LASTEXITCODE)" }
        [void](powercfg /setdcvalueindex SCHEME_CURRENT $SubGuid $SetGuid $DcValue 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "powercfg /setdcvalueindex failed for $SetGuid (exit $LASTEXITCODE)" }
    } finally {
        $ErrorActionPreference = $oldEa
    }
}

# ---- Commands ----------------------------------------------------------------
function Invoke-StrongOn {
    try {
        Invoke-StrongOnCore
    } catch {
        $msg = "ON failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Write-Result -Op 'on' -Status 'error' -Msg $msg
        Write-Host $msg -ForegroundColor Red
        exit 1
    }
}

function Invoke-StrongOnCore {
    Write-Log 'ON: backing up current power-plan values...'
    $scheme = Get-ActiveSchemeGuid
    $backup = [ordered]@{
        scheme = $scheme
        captured = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        settings = [ordered]@{}
    }
    $present = New-Object System.Collections.Generic.List[string]
    $absent  = New-Object System.Collections.Generic.List[string]
    foreach ($alias in $Settings.Keys) {
        $s = $Settings[$alias]
        $v = Get-SettingValue -SubGuid $s.Sub -SetGuid $s.Set
        if ($null -eq $v) {
            $absent.Add($alias) | Out-Null
            $backup.settings[$alias] = $null   # explicitly record absence
            Write-Log "  $alias ($($s.Name)): NOT PRESENT on this machine - skipped."
        } else {
            $present.Add($alias) | Out-Null
            $backup.settings[$alias] = @{ ac = $v.AC; dc = $v.DC }
            Write-Log ("  {0} ({1}): present AC=0x{2:x8} DC=0x{3:x8}" -f $alias, $s.Name, $v.AC, $v.DC)
        }
    }

    # Only (over)write the backup if none exists. This protects the ORIGINAL values
    # if 'on' is run twice (the second run would otherwise back up our own modified state).
    if (-not (Test-Path $BackupFile)) {
        $backup | ConvertTo-Json -Depth 6 | Set-Content -Path $BackupFile -Encoding UTF8
        Write-Log "Backup written to $BackupFile"
    } else {
        Write-Log "Backup already exists - preserved (not overwritten). Using it as restore source."
    }

    # Apply: set each PRESENT setting to 0 (Do nothing / never).
    foreach ($alias in $present) {
        $s = $Settings[$alias]
        Set-SettingValue -SubGuid $s.Sub -SetGuid $s.Set -AcValue 0 -DcValue 0
        Write-Log "  $alias set AC=0 DC=0"
    }
    $oldEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        [void](powercfg /setactive $scheme 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed (exit $LASTEXITCODE)" }
    } finally {
        $ErrorActionPreference = $oldEa
    }

    # Flag + result
    Set-Content -Path $StrongFlag -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding UTF8

    $msg = if ($absent.Count -gt 0) {
        "Strong ON. Present & zeroed: $($present -join ', '). NOT present (skipped, logged): $($absent -join ', ')."
    } else {
        "Strong ON. All settings zeroed: $($present -join ', ')"
    }
    Write-Log $msg
    Write-Result -Op 'on' -Status 'ok' -Msg $msg -Extra @{ present = $present.ToArray(); absent = $absent.ToArray() }
    Write-Host $msg
}

function Invoke-StrongOff {
    param([switch]$IsRestore)
    $opName = if ($IsRestore) { 'restore' } else { 'off' }
    try {
        Invoke-StrongOffCore -IsRestore:$IsRestore
    } catch {
        $msg = "$opName failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Write-Result -Op $opName -Status 'error' -Msg $msg
        Write-Host $msg -ForegroundColor Red
        exit 1
    }
}

function Invoke-StrongOffCore {
    param([switch]$IsRestore)
    $opName = if ($IsRestore) { 'restore' } else { 'off' }
    Write-Log "${opName}: restoring power-plan values..."

    if (-not (Test-Path $BackupFile)) {
        $msg = "No backup file at $BackupFile - nothing to restore. Power plan left unchanged."
        Write-Log $msg 'WARN'
        Write-Result -Op $opName -Status 'no-backup' -Msg $msg
        Write-Host $msg
        return
    }

    $backup = $null
    try {
        $raw = Get-Content $BackupFile -Raw
        $backup = $raw | ConvertFrom-Json
    } catch {
        # Corrupted backup: fall back to Windows defaults for every setting we manage.
        Write-Log "Backup file unreadable: $($_.Exception.Message). Falling back to Windows defaults." 'WARN'
        $scheme = Get-ActiveSchemeGuid
        foreach ($alias in $Settings.Keys) {
            $s = $Settings[$alias]; $d = $Defaults[$alias]
            # Some settings (e.g. LIDACTION) do not exist on every machine; skip them.
            $current = Get-SettingValue -SubGuid $s.Sub -SetGuid $s.Set
            if ($null -eq $current) {
                Write-Log "  $alias not present on this machine - skipped (backup corrupt)" 'WARN'
                continue
            }
            Set-SettingValue -SubGuid $s.Sub -SetGuid $s.Set -AcValue $d.AC -DcValue $d.DC
            Write-Log "  $alias restored to default AC=$($d.AC) DC=$($d.DC) (backup corrupt)" 'WARN'
        }
        $oldEa = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            [void](powercfg /setactive $scheme 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed (exit $LASTEXITCODE)" }
        } finally {
            $ErrorActionPreference = $oldEa
        }
        Remove-Item -Path $StrongFlag -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $BackupFile -Force -ErrorAction SilentlyContinue
        $msg = "Backup was corrupt; restored Windows defaults for all managed settings. Review your power plan manually."
        Write-Result -Op $opName -Status 'corrupt-fallback' -Msg $msg
        Write-Host $msg -ForegroundColor Yellow
        return
    }

    # Restore onto the currently active scheme, not a possibly stale backed-up scheme,
    # in case the user switched plans while keep-awake was active.
    $scheme = Get-ActiveSchemeGuid
    $restored = New-Object System.Collections.Generic.List[string]
    foreach ($alias in $Settings.Keys) {
        $entry = $backup.settings.$alias
        if ($null -eq $entry) { continue }   # was absent at backup time; leave it
        # $entry is a PSCustomObject from ConvertFrom-Json; read .ac/.dc as int.
        $acVal = [int]($entry.ac)
        $dcVal = [int]($entry.dc)
        $s = $Settings[$alias]
        Set-SettingValue -SubGuid $s.Sub -SetGuid $s.Set -AcValue $acVal -DcValue $dcVal
        $restored.Add($alias) | Out-Null
        Write-Log ("  {0} restored AC=0x{1:x8} DC=0x{2:x8}" -f $alias, $acVal, $dcVal)
    }
    $oldEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        [void](powercfg /setactive $scheme 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed (exit $LASTEXITCODE)" }
    } finally {
        $ErrorActionPreference = $oldEa
    }

    Remove-Item -Path $StrongFlag -Force -ErrorAction SilentlyContinue
    # NOTE: we intentionally do NOT delete the backup here. keep-awake.ps1 owns
    # the backup lifecycle: it deletes the backup only when the user explicitly
    # runs 'off' (not on flex disarm), so that arm/disarm cycles preserve the
    # original baseline. This also lets 'restore' remain usable after a strong-off.
    $msg = "$opName complete. Restored: $($restored -join ', ')."
    Write-Log $msg
    Write-Result -Op $opName -Status 'ok' -Msg $msg -Extra @{ restored = $restored.ToArray() }
    Write-Host $msg
}

# ---- Entry -------------------------------------------------------------------
# The command file is written by keep-awake.ps1 as JSON: {"op":"on","id":"<guid>"}.
# We parse op + id here, and echo id back in every result so the parent can reject
# stale/racing results. Fall back to plain-text ("on"/"off"/"restore") for backward
# compatibility and direct manual invocation.
if (-not (Test-Path $CmdFile)) {
    Write-Log "No command file at $CmdFile. Nothing to do." 'WARN'
    Write-Result -Op 'none' -Status 'no-cmd' -Msg 'No strong-cmd file present.'
    exit 0
}
$cmdRaw = Get-Content $CmdFile -Raw
$op = $null
$script:reqId = $null
try {
    $j = $cmdRaw | ConvertFrom-Json -ErrorAction Stop
    if ($j.op) { $op = ([string]$j.op).Trim().ToLower() }
    if ($j.id) { $script:reqId = [string]$j.id }
} catch {
    # Plain-text command file (manual or older caller).
    $op = $cmdRaw.Trim().ToLower()
}
# Consume the command file so a stale/racing task does not re-run it.
Remove-Item -Path $CmdFile -Force -ErrorAction SilentlyContinue
switch ($op) {
    'on'      { Invoke-StrongOn }
    'off'     { Invoke-StrongOff }
    'restore' { Invoke-StrongOff -IsRestore }
    default   {
        Write-Log "Unknown command in strong-cmd: '$op'" 'ERROR'
        Write-Result -Op $op -Status 'unknown' -Msg "Unknown command: $op"
        exit 1
    }
}
