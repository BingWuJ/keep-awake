#!/usr/bin/env pwsh
# keep-awake.ps1 - Core CLI of keep-awake (Windows).
#
# Contract (settled in the 2026-06 grilling session, replaces the old super/flex/normal):
#   on     -> start the daemon. While on AC power it blocks system idle sleep
#             (SetThreadExecutionState ES_CONTINUOUS|ES_SYSTEM_REQUIRED). On battery it
#             holds nothing and says so. The screen is never forced on - it follows the
#             Windows display timeout. Lid close, power button and the power plan are
#             never touched. Nothing survives a reboot; no scheduled tasks, no hooks.
#   off    -> stop the daemon (nothing was changed, so nothing needs restoring) and clean
#             up any leftovers of the OLD keep-awake design: legacy scheduled tasks
#             keep-awake-strong / keep-awake-bootcheck, the power plan backup, flex hooks
#             in pi/Claude settings.json. UAC is requested only when such leftovers exist.
#   status -> report state honestly, including legacy leftovers.
#
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File keep-awake.ps1 on | off | status

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ---- Paths -------------------------------------------------------------------
$RepoScripts = Split-Path -Parent $MyInvocation.MyCommand.Path
$Watcher     = Join-Path $RepoScripts 'awake-watcher.ps1'

$StateDir = Join-Path $env:USERPROFILE '.keep-awake'
$ModeFile = Join-Path $StateDir 'mode'
$InfoFile = Join-Path $StateDir 'info'
$PidFile  = Join-Path $StateDir 'awake.pid'
$StopFile = Join-Path $StateDir 'stop'
$StateOut = Join-Path $StateDir 'watcher-state'
# Legacy files from the old super/flex design (cleaned up by off/uninstall, never created again):
$LegacyStrong = Join-Path $StateDir 'strong'
$LegacyCmd    = Join-Path $StateDir 'strong-cmd'
$LegacyResult = Join-Path $StateDir 'strong-result.json'
$LegacyBackup = Join-Path $StateDir 'power-backup.json'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

$LegacyTaskNames = @('keep-awake-strong', 'keep-awake-bootcheck')

# ---- Helpers -----------------------------------------------------------------
function Get-Now { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }

function Get-PowerLine {
    # Online / Offline / Unknown. Unknown must never be treated as "keep awake".
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return [string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
    } catch { return 'Unknown' }
}

function Test-WatcherRunning {
    if (-not (Test-Path $PidFile)) { return $false }
    # A zero-byte file yields $null from -Raw; guard it (same crash class as Invoke-On).
    $rawPid = Get-Content $PidFile -Raw -ErrorAction SilentlyContinue
    $pidVal = if ($null -ne $rawPid) { $rawPid.Trim() } else { '' }
    $id = 0
    if (-not [int]::TryParse($pidVal, [ref]$id)) { return $false }
    try {
        $null = Get-Process -Id $id -ErrorAction Stop
        # Fail-closed: only trust the PID when we can confirm it runs awake-watcher.ps1.
        # If the CIM query fails or returns nothing we cannot verify ownership - returning
        # $true here would let 'on' fake success on a recycled PID (never fake).
        $cmd = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop).CommandLine } catch { '' }
        return ($cmd -like '*awake-watcher.ps1*')
    } catch { return $false }
}

function Test-TaskRegistered {
    param([string]$Name)
    $null = schtasks /query /tn $Name 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-LegacyArtifacts {
    $found = @()
    foreach ($t in $LegacyTaskNames) { if (Test-TaskRegistered -Name $t) { $found += "task:$t" } }
    foreach ($f in @($LegacyStrong, $LegacyCmd, $LegacyResult, $LegacyBackup)) {
        if (Test-Path $f) { $found += "file:$(Split-Path -Leaf $f)" }
    }
    return $found
}

# ---- Daemon lifecycle --------------------------------------------------------
function Start-Watcher {
    if (Test-WatcherRunning) { return }
    if (-not (Test-Path $Watcher)) { throw "Daemon script not found: $Watcher" }
    Remove-Item -Path $StopFile -Force -ErrorAction SilentlyContinue
    # Clear any state left by a previous daemon run so the parent's post-start poll can
    # only ever see state published by the NEW daemon (stale 'holding-ac' must not count).
    Remove-Item -Path $StateOut -Force -ErrorAction SilentlyContinue
    # Kill orphaned watchers whose pid file was already removed (parent killed mid-shutdown).
    $me = $PID
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*awake-watcher.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    if (Test-WatcherRunning) { return }
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $exe = if ($pwsh) { $pwsh.Source } else { 'powershell.exe' }
    $null = Start-Process -FilePath $exe `
        -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$Watcher `
        -WindowStyle Hidden -PassThru
    # Wait briefly for the daemon to write its pid file.
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline -and -not (Test-WatcherRunning)) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-WatcherRunning)) {
        throw "Daemon failed to start or did not write its pid file. Check $StateDir\awake-watcher.log"
    }
}

function Stop-Watcher {
    # Returns $true only with positive evidence that no watcher of ours is running.
    # On failure it KEEPS the stop sentinel and pid file (a live daemon will still see
    # the sentinel, and a retry keeps working) so success is never faked. PRD §2/§3.3/§4.
    # Always arm the sentinel FIRST: a daemon in its startup window (Add-Type, mutex,
    # first publish) owns no pid file yet, and 'off must win' means it must still see
    # the stop request. Stale sentinels are harmless and removed by the next 'on'.
    Set-Content -Path $StopFile -Value 'stop' -Encoding ASCII

    if (Test-Path $PidFile) {
        # Quick staleness check: if the pid file names a dead process there is nothing
        # to stop and no reason to sit through the graceful wait.
        $pidVal0 = Get-Content $PidFile -Raw -ErrorAction SilentlyContinue
        $id0 = 0
        $alive0 = $false
        if ([int]::TryParse("$pidVal0".Trim(), [ref]$id0)) {
            $alive0 = $null -ne (Get-Process -Id $id0 -ErrorAction SilentlyContinue)
        }
        if (-not $alive0) {
            Remove-Item -Path $PidFile,$StopFile -Force -ErrorAction SilentlyContinue
            return $true
        }
    } else {
        # Startup-window grace: let a just-started daemon publish its pid file.
        $deadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $deadline -and -not (Test-Path $PidFile)) { Start-Sleep -Milliseconds 250 }
        if (-not (Test-Path $PidFile)) { return $true }   # nothing appeared: keep sentinel
    }

    # Graceful: the daemon removes its pid file once it has seen the sentinel.
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline -and (Test-Path $PidFile)) { Start-Sleep -Milliseconds 300 }

    if (Test-Path $PidFile) {
        # Escalate - but only against a process we can PROVE is our watcher. A recycled
        # PID belongs to someone else, and a pid file naming THIS process must never
        # trigger a self-kill.
        $pidVal = Get-Content $PidFile -Raw -ErrorAction SilentlyContinue
        $id = 0
        $ours = $false
        if ([int]::TryParse("$pidVal".Trim(), [ref]$id) -and $id -ne $PID) {
            $cmd = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop).CommandLine } catch { '' }
            if ($cmd -like '*awake-watcher.ps1*') { $ours = $true }
        }
        if ($ours) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
            if (Get-Process -Id $id -ErrorAction SilentlyContinue) {
                Write-Host "⚠ 强制停止守护进程（PID $id）失败，它可能仍在运行。" -ForegroundColor Red
                return $false   # keep sentinel + pid file for retry / late self-exit
            }
        }
        # Stale (dead, foreign or self-naming) pid file: it is ours, remove it.
        Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $StopFile -Force -ErrorAction SilentlyContinue
    return $true
}

# ---- Legacy cleanup (old super/flex design) ----------------------------------
# The old version changed the power plan through an elevated scheduled task. If any of
# that is still on the machine, one elevated helper restores the plan from the backup and
# unregisters the tasks. It never creates anything; it only restores and removes.
function Invoke-LegacyCleanup {
    $artifacts = Get-LegacyArtifacts
    if ($artifacts.Count -eq 0) { return $true }

    Write-Host "检测到旧版残留: $($artifacts -join ', ')" -ForegroundColor Yellow

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $exe = if ($pwsh) { $pwsh.Source } else { 'powershell.exe' }

    # Settings the old version could have touched (subset of the old strong-op.ps1 GUIDs).
    $map = [ordered]@{
        LIDACTION     = @{ Sub = '4f971e89-eebd-4455-a8de-9e59040e7347'; Set = '5ca83367-6e45-459f-a27b-476b1d01c936' }
        STANDBYIDLE   = @{ Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' }
        HIBERNATEIDLE = @{ Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '9d7815a6-7ee4-497e-8888-515a05f02364' }
        UNATTENDSLEEP = @{ Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '7bc4f55f-8a8f-4ac3-8441-6c5b2f4a2c5a' }
    }

    # Read + VALIDATE the backup. The generated script runs as ADMIN, so a corrupt or
    # tampered backup must abort with an honest report - never be interpolated blindly.
    $restoreLines = @()
    $backupJson = $null
    $backupFileExists = Test-Path $LegacyBackup
    if ($backupFileExists) {
        try { $backupJson = Get-Content $LegacyBackup -Raw | ConvertFrom-Json } catch { $backupJson = $null }
        if ($null -eq $backupJson) {
            Write-Host "⚠ 备份 power-backup.json 无法解析，无法如实恢复电源计划。保留残留。" -ForegroundColor Red
            Write-Host "  请手动恢复电源计划或删除旧计划任务后，重跑 off / uninstall.ps1。" -ForegroundColor Yellow
            return $false
        }
        $scheme = [string]$backupJson.scheme
        if ($scheme -notmatch '^[0-9a-fA-F-]{36}$') {
            Write-Host "⚠ 备份 scheme 字段异常，拒绝生成提权脚本。保留残留。" -ForegroundColor Red
            return $false
        }
        if ($backupJson.settings) {
            foreach ($p in $backupJson.settings.PSObject.Properties) {
                $alias = $p.Name; $v = $p.Value
                if ($null -eq $v -or -not $map.Contains($alias)) { continue }
                $ac = $v.ac; $dc = $v.dc
                if ($null -eq $ac -or $null -eq $dc -or "$ac" -notmatch '^\d+$' -or "$dc" -notmatch '^\d+$') {
                    Write-Host "⚠ 备份项 $alias 的 ac/dc 不是整数，拒绝生成提权脚本。保留残留。" -ForegroundColor Red
                    return $false
                }
                $g = $map[$alias]
                $restoreLines += "powercfg /setacvalueindex SCHEME_CURRENT $($g.Sub) $($g.Set) $ac 2>&1 | Out-Null; if (`$LASTEXITCODE -ne 0) { `$script:restoreFailed = `$true }"
                $restoreLines += "powercfg /setdcvalueindex SCHEME_CURRENT $($g.Sub) $($g.Set) $dc 2>&1 | Out-Null; if (`$LASTEXITCODE -ne 0) { `$script:restoreFailed = `$true }"
            }
            if ($restoreLines.Count -gt 0) {
                $restoreLines += "powercfg /setactive $scheme 2>&1 | Out-Null; if (`$LASTEXITCODE -ne 0) { `$script:restoreFailed = `$true }"
            }
        }
    }
    $taskLines = @($LegacyTaskNames | ForEach-Object {
        "Unregister-ScheduledTask -TaskName '$_' -Confirm:`$false -ErrorAction SilentlyContinue"
    })
    # Single-quote literals: escape embedded quotes by doubling (paths can be odd).
    $resultPathLit = $LegacyResult.Replace("'", "''")
    $nowLit = (Get-Now).Replace("'", "''")

    $content = @"
`$ErrorActionPreference = 'Continue'
`$script:restoreFailed = `$false
Import-Module ScheduledTasks -ErrorAction SilentlyContinue

# --- restore power plan values from the old version's backup (if any) ---
$($restoreLines -join "`r`n")

# --- unregister the old elevated tasks ---
$($taskLines -join "`r`n")

@{ restored = $(if ($restoreLines.Count -gt 0) { "`$script:restoreFailed -eq `$false" } else { "`$false" }); at = '$nowLit' } |
    ConvertTo-Json -Compress | Set-Content -Path '$resultPathLit' -Encoding UTF8
if (`$script:restoreFailed) { exit 1 }
"@
    $tmp = Join-Path $env:TEMP ("ka-legacy-" + [System.IO.Path]::GetRandomFileName() + ".ps1")
    Set-Content -Path $tmp -Value $content -Encoding UTF8
    # Move any previous result file aside instead of deleting it: until the elevated run
    # finishes we do not know the outcome, so evidence must survive a failure/cancel.
    $staleResult = "$LegacyResult.stale"
    if (Test-Path $LegacyResult) {
        Move-Item -Path $LegacyResult -Destination $staleResult -Force -ErrorAction SilentlyContinue
    }
    try {
        $p = Start-Process -FilePath $exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp `
            -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($p.ExitCode -ne 0) {
            Remove-Item -Path $staleResult -Force -ErrorAction SilentlyContinue
            Write-Host "⚠ 清理脚本失败（退出码 $($p.ExitCode)），电源计划可能未被恢复。保留残留。" -ForegroundColor Yellow
            return $false
        }
        $restored = $false
        try {
            if (Test-Path $LegacyResult) {
                $r = Get-Content $LegacyResult -Raw | ConvertFrom-Json
                $restored = ([bool]$r.restored)
            }
        } catch { $restored = $false }
        if ($restoreLines.Count -gt 0 -and -not $restored) {
            Remove-Item -Path $staleResult -Force -ErrorAction SilentlyContinue
            Write-Host "⚠ 清理脚本自报恢复未成功。保留残留，勿当作已恢复。" -ForegroundColor Yellow
            return $false
        }
        Remove-Item -Path $LegacyStrong,$LegacyCmd,$LegacyResult,$LegacyBackup,$staleResult -Force -ErrorAction SilentlyContinue
        if ((Get-LegacyArtifacts).Count -eq 0) {
            Write-Host "✓ 旧版残留已清理（电源计划已按备份恢复，旧计划任务已删除）。" -ForegroundColor Green
            return $true
        }
        Write-Host "⚠ 清理脚本已运行，但仍有残留，请以管理员运行 uninstall.ps1 复核。" -ForegroundColor Yellow
        return $false
    } catch {
        # UAC declined / failed: restore the previous result file (evidence kept).
        if (Test-Path $staleResult) { Move-Item -Path $staleResult -Destination $LegacyResult -Force -ErrorAction SilentlyContinue }
        Write-Host "⚠ UAC 被取消或失败: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  旧残留仍在。可稍后以管理员运行 uninstall.ps1，或手动删除旧计划任务。" -ForegroundColor Yellow
        return $false
    } finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}

# ---- Legacy hooks removal (old flex design; never creates files) -------------
function Remove-LegacyHooks {
    $targets = @(
        (Join-Path $env:USERPROFILE '.pi\agent\settings.json'),
        (Join-Path $env:USERPROFILE '.claude\settings.json')
    )
    foreach ($file in $targets) {
        if (-not (Test-Path $file)) { continue }
        try {
            $j = Get-Content $file -Raw | ConvertFrom-Json
            if (-not $j.hooks) { continue }
            $changed = $false
            foreach ($evt in @('UserPromptSubmit','Stop')) {
                $arr = $j.hooks.$evt
                if (-not $arr) { continue }
                $marker = if ($evt -eq 'UserPromptSubmit') { 'arm' } else { 'disarm' }
                # Word-boundary match: a bare '*arm*' would also match 'disarm' and
                # delete a Stop-style entry from UserPromptSubmit. Only entries whose
                # marker stands as its own word count as ours.
                $kept = @($arr | Where-Object {
                    -not ($_.command -and $_.command -like '*keep-awake.ps1*' -and $_.command -match "\b$marker\b")
                })
                if ($kept.Count -ne @($arr).Count) {
                    $changed = $true
                    if ($kept.Count -gt 0) { $j.hooks.$evt = $kept }
                    else { $j.hooks.PSObject.Properties.Remove($evt) }
                }
            }
            if ($changed) {
                $j | ConvertTo-Json -Depth 10 | Set-Content -Path $file -Encoding UTF8
                Write-Host "✓ 已从 $file 移除旧版 keep-awake 钩子。" -ForegroundColor Green
            }
        } catch {
            Write-Host "⚠ 检查 $file 的旧钩子失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# ---- Commands ----------------------------------------------------------------
function Invoke-On {
    $pl = Get-PowerLine
    if ($pl -eq 'Unknown') {
        Write-Host "❌ 读不到电源状态（插电/电池）。按契约不挡睡眠，也不假装在挡。" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-WatcherRunning)) {
        Start-Watcher
    }
    Set-Content -Path $ModeFile -Value 'on' -Encoding ASCII
    @{ mode = 'on'; started = (Get-Now) } | ConvertTo-Json -Depth 3 | Set-Content -Path $InfoFile -Encoding UTF8

    # The daemon's published state is the single source of truth. This process's own
    # reading of the power source is NOT proof the system is actually being held:
    # the daemon may have hit an unreadable power state or a failed API call.
    # Wait for a TERMINAL published state. The daemon publishes 'starting' first, so a
    # mere file-existence check cannot mistake a stale or transitional value for success.
    $deadline = (Get-Date).AddSeconds(8)
    $st = ''
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $StateOut) {
            # A zero-byte file (mid-write race) yields $null from -Raw; guard it and keep
            # polling instead of crashing on .Trim() - empty is 'not yet', never success.
            $raw = Get-Content $StateOut -Raw -ErrorAction SilentlyContinue
            $s = if ($null -ne $raw) { $raw.Trim() } else { '' }
            if ($s -in @('holding-ac','released-battery','error-power-unknown')) { $st = $s; break }
        }
        Start-Sleep -Milliseconds 250
    }
    switch ($st) {
        'holding-ac' {
            Write-Host "🔆 ON：插电中，挡住系统空闲睡眠。" -ForegroundColor Green
        }
        'released-battery' {
            Write-Host "◐ ON：当前用电池，未挡睡眠（宁可不挡，不假装醒着）。插上电源后自动开始挡。" -ForegroundColor Yellow
        }
        'error-power-unknown' {
            Write-Host "⚠ ON：守护进程读不到电源状态或挡睡眠失败，当前未挡（不假装在挡）。" -ForegroundColor Red
            exit 1
        }
        default {
            Write-Host "⚠ ON：守护进程未报告状态，不能确认在挡。检查 $StateDir\awake-watcher.log" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "   屏幕按 Windows 显示超时自行变黑；合盖/电源键/电源计划不动。用完记得 off。" -ForegroundColor Gray
}

function Invoke-Off {
    $stopped = Stop-Watcher
    if (-not $stopped) {
        Write-Host "⚠ OFF 未完成：守护进程可能仍在运行。停止哨兵与 pid 已保留，请重试 off。" -ForegroundColor Red
        Write-Host "  若反复失败，请在任务管理器结束命令行含 awake-watcher.ps1 的 pwsh 进程。" -ForegroundColor Yellow
        exit 1
    }
    $legacyClean = Invoke-LegacyCleanup
    Remove-LegacyHooks
    # Verify deletions: a locked file must not silently fake a clean shutdown.
    $failed = @()
    foreach ($f in @($ModeFile, $InfoFile, $StateOut)) {
        if (Test-Path $f) {
            Remove-Item -Path $f -Force -ErrorAction SilentlyContinue
            if (Test-Path $f) { $failed += (Split-Path -Leaf $f) }
        }
    }
    if ($failed.Count -gt 0) {
        Write-Host "⚠ OFF 未完全完成：以下状态文件删除失败（可能被占用）: $($failed -join ', ')" -ForegroundColor Red
        exit 1
    }
    if (-not $legacyClean) {
        Write-Host "⚠ OFF 未完全完成：守护进程已停，但旧版清理失败。残留与备份已保留，请处理错误后重试。" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "🌙 OFF：守护进程已停，恢复正常睡眠。电源计划从未被新版本修改。" -ForegroundColor Green
}

function Invoke-Status {
    $pl = Get-PowerLine
    $plText = switch ($pl) { 'Online' { '插电' } 'Offline' { '电池' } default { '读不到' } }
    if (Test-WatcherRunning) {
        $rawPid = Get-Content $PidFile -Raw -ErrorAction SilentlyContinue
        $pidVal = if ($null -ne $rawPid) { $rawPid.Trim() } else { '?' }
        $st = ''
        if (Test-Path $StateOut) {
            $rawSt = Get-Content $StateOut -Raw -ErrorAction SilentlyContinue
            if ($null -ne $rawSt) { $st = $rawSt.Trim() }
        }
        switch ($st) {
            'holding-ac'          { Write-Host "状态: 🔆 挡住系统空闲睡眠（插电）    守护进程 PID: $pidVal" }
            'released-battery'    { Write-Host "状态: ◐ 已开启但未挡睡眠（当前用电池）    守护进程 PID: $pidVal" }
            'error-power-unknown' { Write-Host "状态: ⚠ 电源状态读取失败，未挡睡眠    守护进程 PID: $pidVal" }
            default               { Write-Host "状态: 🔆 守护进程运行中（状态: $st）    PID: $pidVal" }
        }
        if (Test-Path $InfoFile) {
            try { $info = Get-Content $InfoFile -Raw | ConvertFrom-Json; Write-Host "  started: $($info.started)" } catch { }
        }
    } else {
        Write-Host "状态: 🌙 未开启（正常睡眠行为）"
    }
    Write-Host "电源: $plText"
    Write-Host "屏幕: 不强制常亮，跟随 Windows 显示超时自动变黑。"
    Write-Host "合盖/电源键/电源计划: 从不修改。"
    $legacy = Get-LegacyArtifacts
    if ($legacy.Count -gt 0) {
        Write-Host "⚠ 检测到旧版残留（运行 off 或 uninstall.ps1 清理）: $($legacy -join ', ')" -ForegroundColor Yellow
    }
}

# ---- Entry -------------------------------------------------------------------
$cmd = if ($Rest -and $Rest.Count -ge 1) { $Rest[0] } else { 'status' }
switch ($cmd) {
    'on'     { Invoke-On }
    'off'    { Invoke-Off }
    'status' { Invoke-Status }
    ''       { Invoke-Status }
    default {
        Write-Host "未知命令: $cmd" -ForegroundColor Red
        Write-Host "用法: keep-awake.ps1 on | off | status"
        Write-Host "（旧版 super/flex/normal、arm/disarm、install-task、restore 已按新契约移除）"
        exit 1
    }
}
