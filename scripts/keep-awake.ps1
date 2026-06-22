#!/usr/bin/env pwsh
# keep-awake.ps1 - Core CLI for keep-awake (Windows).
#
# Keeps a Windows PC awake while AI agents / long tasks run, by combining two levers:
#   Lever 1: a hidden daemon (awake-watcher.ps1) holding SetThreadExecutionState.
#   Lever 2: powercfg setting standby/hibernate timeouts (and lid action, if present) to 0,
#            invoked through a one-time HIGHEST-privilege scheduled task so no UAC later.
#
# Three modes (mirrors the macOS original):
#   normal - lever 1 only; awake while the lid is open (lid-close still sleeps).
#   super  - lever 1 + lever 2 always on; never sleeps (lid/unplug/battery) until 'off'.
#   flex   - lever 1 + lever 2 engaged only while an agent works; auto-released on Stop.
#            Driven by pi/Claude Code hooks (UserPromptSubmit -> arm, Stop -> disarm).
#
# Usage:
#   keep-awake.ps1 on <super|flex|normal>
#   keep-awake.ps1 off [--sleep-now]
#   keep-awake.ps1 status
#   keep-awake.ps1 arm | disarm               (hook-internal; do not call manually)
#   keep-awake.ps1 restore                    (manually restore power plan from backup)
#   keep-awake.ps1 install-task | uninstall-task
#   keep-awake.ps1 install-hook | uninstall-hook

[CmdletBinding()]
param(
    # Accept the subcommand and its args positionally so users can run:
    #   keep-awake.ps1 on normal   /  keep-awake.ps1 off --sleep-now
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ---- Paths -------------------------------------------------------------------
$RepoScripts = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeepAwake   = Join-Path $RepoScripts 'keep-awake.ps1'
$Watcher     = Join-Path $RepoScripts 'awake-watcher.ps1'
$StrongOp    = Join-Path $RepoScripts 'strong-op.ps1'

$StateDir    = Join-Path $env:USERPROFILE '.keep-awake'
$ModeFile    = Join-Path $StateDir 'mode'
$InfoFile    = Join-Path $StateDir 'info'
$PidFile     = Join-Path $StateDir 'awake.pid'
$StopFile    = Join-Path $StateDir 'stop'
$StrongFlag  = Join-Path $StateDir 'strong'
$StrongCmd   = Join-Path $StateDir 'strong-cmd'
$StrongResult= Join-Path $StateDir 'strong-result.json'
$BackupFile  = Join-Path $StateDir 'power-backup.json'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

$TaskName    = 'keep-awake-strong'
$BootTaskName= 'keep-awake-bootcheck'

# ---- Helpers -----------------------------------------------------------------
function Get-Now { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
function Get-CurrentMode {
    if (Test-Path $ModeFile) { return (Get-Content $ModeFile -Raw).Trim() }
    return ''
}
function Get-FriendlyMode {
    param([string]$m)
    switch ($m) { 'super' { 'Super' }; 'flex' { 'Flex' }; 'normal' { 'Normal' }; default { $m } }
}

# Is the watcher daemon alive?
function Test-WatcherRunning {
    if (-not (Test-Path $PidFile)) { return $false }
    $pidVal = (Get-Content $PidFile -Raw -ErrorAction SilentlyContinue).Trim()
    $id = 0
    if (-not [int]::TryParse($pidVal, [ref]$id)) { return $false }
    try {
        $p = Get-Process -Id $id -ErrorAction Stop
        # Avoid misidentifying a recycled PID: confirm it's actually pwsh running our script.
        $cmd = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop).CommandLine } catch { '' }
        # If CIM query fails (service unavailable/permission), trust the PID rather than declaring it dead.
        if (-not $cmd) { return $true }
        return ($cmd -like '*awake-watcher.ps1*')
    } catch { return $false }
}

# Is a keep-awake scheduled task registered?
function Test-TaskRegistered {
    param([string]$Name = $TaskName)
    $null = schtasks /query /tn $Name 2>$null
    return ($LASTEXITCODE -eq 0)
}

# ---- Lever 1: watcher daemon ------------------------------------------------
function Start-Watcher {
    if (Test-WatcherRunning) { return }
    if (-not (Test-Path $Watcher)) { throw "Watcher script not found: $Watcher" }
    Remove-Item -Path $StopFile -Force -ErrorAction SilentlyContinue
    # Clean up any orphaned awake-watcher process whose PID file has been removed
    # but which is still holding the mutex (can happen if a parent script is killed
    # while the watcher is shutting down).
    $me = $PID
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*awake-watcher.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    if (Test-WatcherRunning) { return }
    # Find pwsh.exe; fall back to powershell.exe (Windows PowerShell 5) if PS7 is absent.
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $exe = if ($pwsh) { $pwsh.Source } else { 'powershell.exe' }
    $proc = Start-Process -FilePath $exe `
        -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$Watcher `
        -WindowStyle Hidden -PassThru
    # Wait briefly for the daemon to write its PID file and assert the mutex.
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline -and -not (Test-WatcherRunning)) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-WatcherRunning)) {
        throw "awake-watcher 启动失败或 PID 文件未写入。请检查 $StateDir\awake-watcher.log"
    }
}
function Stop-Watcher {
    # Graceful: create the stop sentinel; the daemon exits within ~5s.
    if (Test-Path $PidFile) {
        Set-Content -Path $StopFile -Value 'stop' -Encoding ASCII
        $deadline = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $deadline -and (Test-Path $PidFile)) { Start-Sleep -Milliseconds 300 }
    }
    # Force kill if still alive.
    if (Test-Path $PidFile) {
        $pidVal = (Get-Content $PidFile -Raw -ErrorAction SilentlyContinue).Trim()
        $id = 0
        if ([int]::TryParse($pidVal, [ref]$id)) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $StopFile -Force -ErrorAction SilentlyContinue
}

# ---- Lever 2: strong-op via scheduled task (passwordless after install) ------
function Invoke-StrongOp {
    param([ValidateSet('on','off','restore')][string]$Op)
    # Tag this request so we can ignore stale results from a previous/racing task instance.
    $reqId = [Guid]::NewGuid().ToString('N')
    @{ op = $Op; id = $reqId } | ConvertTo-Json -Depth 3 -Compress | Set-Content -Path $StrongCmd -Encoding UTF8
    Remove-Item -Path $StrongResult -Force -ErrorAction SilentlyContinue
    if (-not (Test-TaskRegistered)) {
        Write-Host "  (计划任务 $TaskName 未注册 - 杠杆② [合盖防护] 未生效。运行: keep-awake.ps1 install-task)" -ForegroundColor Yellow
        return $false
    }
    # Best-effort: stop any stuck previous instance (may require admin; ignored if it fails).
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { }
    Start-Sleep -Milliseconds 200
    # Trigger the HIGHEST-privilege task synchronously.
    $null = schtasks /run /tn $TaskName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  (schtasks /run 失败 - 杠杆② 未触发。退出码 $LASTEXITCODE)" -ForegroundColor Yellow
        return $false
    }
    # Poll strong-result.json, but only accept the result for *this* request.
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $StrongResult) {
            try {
                $r = Get-Content $StrongResult -Raw | ConvertFrom-Json
                if ($r.id -eq $reqId) { break }
            } catch { }
        }
        Start-Sleep -Milliseconds 500
    }
    if (Test-Path $StrongResult) {
        try {
            $r = Get-Content $StrongResult -Raw | ConvertFrom-Json
            if ($r.id -ne $reqId) {
                Write-Host "  杠杆② 返回了旧的/不匹配的结果。检查 $StateDir\strong-op.log" -ForegroundColor Yellow
                return $false
            }
            if ($r.status -eq 'ok') {
                if ($r.msg) { Write-Host "  $($r.msg)" -ForegroundColor Cyan }
                return $true
            } else {
                Write-Host "  杠杆② 返回: $($r.status) - $($r.msg)" -ForegroundColor Yellow
                return $false
            }
        } catch { return $false }
    }
    Write-Host "  杠杆② 超时（未收到完成信号）。检查 $StateDir\strong-op.log" -ForegroundColor Yellow
    return $false
}

function Print-TaskAuthGuide {
    Write-Host ""
    Write-Host "🔑 合盖防护需要一次性授权（此后免密）。在 PowerShell 终端运行：" -ForegroundColor Cyan
    Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$RepoScripts\..\install.ps1`" -TasksOnly" -ForegroundColor White
    Write-Host "   （会弹一次 UAC，注册最高权限计划任务 $TaskName）" -ForegroundColor Gray
    Write-Host ""
}

# ---- Commands ----------------------------------------------------------------
function Invoke-On {
    param([string]$Mode)
    if ($Mode -notin 'super','flex','normal') {
        Write-Host "❌ 用法: on <super|flex|normal>" -ForegroundColor Red
        exit 1
    }
    Set-Content -Path $ModeFile -Value $Mode -Encoding ASCII
    @{ mode = $Mode; started = (Get-Now) } | ConvertTo-Json -Depth 3 | Set-Content -Path $InfoFile -Encoding UTF8

    switch ($Mode) {
        'normal' {
            Uninstall-Hook $null  # silently remove any flex hooks if present
            # If switching directly from super/flex, make sure lever 2 is restored.
            $restored = $false
            if ((Test-Path $StrongFlag) -or (Test-Path $BackupFile)) {
                $restored = Invoke-StrongOp -Op 'off'
                if ($restored) { Remove-Item -Path $BackupFile -Force -ErrorAction SilentlyContinue }
            } else {
                Remove-Item -Path $StrongCmd -Force -ErrorAction SilentlyContinue
                $restored = $true
            }
            if ($restored) {
                Remove-Item -Path $StrongFlag -Force -ErrorAction SilentlyContinue
                Start-Watcher
                Write-Host "🔆 NORMAL: 开盖时不息屏/不空闲睡眠；合盖/电源按钮照常触发睡眠。" -ForegroundColor Green
                Write-Host "   （接外屏+电源时合盖进入 Windows 现代待机继续运行——硬件行为，本工具不控制）" -ForegroundColor Gray
            } else {
                Write-Host "⚠️ 无法从 super/flex 切到 normal：杠杆② 恢复失败。合盖防护仍可能开启。" -ForegroundColor Yellow
                Write-Host "   请检查计划任务状态或运行: keep-awake.ps1 restore / install-task" -ForegroundColor Yellow
                exit 1
            }
        }
        'super' {
            Uninstall-Hook $null
            Start-Watcher
            $ok = Invoke-StrongOp -Op 'on'
            if ($ok -and (Test-Path $StrongFlag)) {
                Write-Host "🛡️ SUPER: 永不睡眠（合盖/拔外屏/电池），直到运行 'off'。" -ForegroundColor Green
                Write-Host "   ⚠️ 合盖无外屏时持续高负载会发热；电池下也不睡。用完务必 off。" -ForegroundColor Yellow
            } else {
                Write-Host "🔆 基础防睡眠已开，但 SUPER 的合盖防护还需一步：" -ForegroundColor Cyan
                Print-TaskAuthGuide
            }
        }
        'flex' {
            Install-Hook $null
            Start-Watcher
            $ok = Invoke-StrongOp -Op 'on'
            if ($ok -and (Test-Path $StrongFlag)) {
                Write-Host "🛡️ FLEX: 干活时全防护（含合盖），Agent 停下自动放开，下次消息再自动唤醒。" -ForegroundColor Green
            } else {
                Write-Host "🔆 FLEX 基础防护已开（干活时）；合盖防护还需一步：" -ForegroundColor Cyan
                Print-TaskAuthGuide
            }
        }
    }
}

function Invoke-Off {
    param([string[]]$Args)
    $sleepNow = $Args -contains '--sleep-now'
    Stop-Watcher
    # Always restore power plan if we (may have) modified it.
    $restored = $false
    if ((Test-Path $StrongFlag) -or (Test-Path $BackupFile)) {
        $restored = Invoke-StrongOp -Op 'off'
        if ($restored) {
            # strong-op only restored values; we own the backup lifecycle.
            Remove-Item -Path $BackupFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "⚠️ 守护进程已停，但杠杆② 需提权恢复。手动运行: keep-awake.ps1 restore" -ForegroundColor Yellow
        }
    } else {
        Remove-Item -Path $StrongCmd -Force -ErrorAction SilentlyContinue
        $restored = $true
    }
    Uninstall-Hook $null
    # Only remove the strong flag and mode info if we are confident the power plan is restored.
    if ($restored) {
        Remove-Item -Path $StrongFlag,$ModeFile,$InfoFile -Force -ErrorAction SilentlyContinue
        Write-Host "🌙 已停止。恢复正常睡眠行为。" -ForegroundColor Green
    } else {
        # Keep StrongFlag so bootcheck/statusline can still detect the residual no-sleep state.
        Remove-Item -Path $ModeFile,$InfoFile -Force -ErrorAction SilentlyContinue
        Write-Host "⚠️ 守护进程与 hooks 已停，但杠杆② 恢复可能未成功。请手动运行: keep-awake.ps1 restore" -ForegroundColor Yellow
    }
    if ($sleepNow) {
        # SetSuspendState: first arg 0=standby/sleep, 1=hibernate; force=1; disableWakeEvent=0.
        Write-Host "💤 立即睡眠…" -ForegroundColor Cyan
        $null = & rundll32.exe powrprof.dll,SetSuspendState 0,1,0 2>$null
    }
}

function Invoke-Status {
    $mode = Get-CurrentMode
    if (Test-WatcherRunning) {
        $pidVal = (Get-Content $PidFile -Raw).Trim()
        Write-Host "状态: 🔆 保持唤醒 · $(Get-FriendlyMode $mode)    守护进程 PID: $pidVal"
        if (Test-Path $InfoFile) {
            try {
                $info = Get-Content $InfoFile -Raw | ConvertFrom-Json
                Write-Host "  started: $($info.started)"
            } catch { }
        }
    } else {
        Write-Host "状态: 🌙 未保持唤醒（正常睡眠）    上次模式: $(Get-FriendlyMode $mode)"
    }
    if ((Test-Path $StrongFlag) -or ((Test-Path $BackupFile))) {
        Write-Host "合盖防护: 🛡️ 开（standby/hibernate timeout=0）"
    } else {
        Write-Host "合盖防护: — 关（默认睡眠行为）"
    }
    Write-Host "计划任务 $TaskName : $(if (Test-TaskRegistered) {'已注册（免密可用）'} else {'未注册'})"
}

# UserPromptSubmit hook: engage protection while working (silent unless wrong mode).
function Invoke-Arm {
    if ((Get-CurrentMode) -ne 'flex') { exit 0 }
    Start-Watcher
    # The strong flag is the authoritative sign that lever 2 is active.
    # The backup file is intentionally kept across disarm/arm cycles to preserve
    # the original baseline, so we must NOT use it as an armed indicator.
    if (Test-Path $StrongFlag) { return }
    $null = Invoke-StrongOp -Op 'on'
    exit 0
}
# Stop hook: release when the agent stops; keep mode/hooks (silent).
function Invoke-Disarm {
    if ((Get-CurrentMode) -ne 'flex') { exit 0 }
    Stop-Watcher
    if (Test-Path $StrongFlag) {
        $ok = Invoke-StrongOp -Op 'off'
        if (-not $ok) {
            # Leave StrongFlag in place so the next arm and status line know
            # the power plan may still be in no-sleep mode.
            exit 0
        }
    }
    exit 0
}

function Invoke-Restore {
    Write-Host "恢复电源计划…" -ForegroundColor Cyan
    # restore must work without a backup file being considered a success,
    # because the user explicitly asked to recover from a potentially stuck state.
    $ok = Invoke-StrongOp -Op 'restore'
    if ($ok) {
        Write-Host "✓ 已尝试按备份恢复电源计划。" -ForegroundColor Green
        Remove-Item -Path $StrongFlag -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "⚠️ 恢复未成功，Strong 标志保留，请检查 $StateDir\strong-op.log" -ForegroundColor Yellow
    }
}

# ---- Hook install/uninstall (pi + Claude Code) ------------------------------
# Safe-merge UserPromptSubmit -> arm and Stop -> disarm into settings, idempotent.
function Get-HookShell {
    # Prefer PowerShell 7, fall back to Windows PowerShell 5.1.
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return 'powershell.exe'
}
function Get-HookTargets {
    $targets = @()
    # pi: ~/.pi/agent/settings.json  (hooks shape mirrors Claude Code)
    $pi = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $pi) -Force | Out-Null
    $targets += $pi
    # Claude Code: ~/.claude/settings.json
    $cc = Join-Path $env:USERPROFILE '.claude\settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cc) -Force | Out-Null
    $targets += $cc
    return $targets
}
function Get-HookCommand {
    param([string]$Shell = (Get-HookShell))
    # Quote the shell path so spaces (default PS7 install) don't break parsing.
    return "`"$Shell`" -ExecutionPolicy Bypass -File `"$RepoScripts\keep-awake.ps1`" arm *> `$null; if (`$LASTEXITCODE -ne 0) { exit 0 }"
}
function Get-DisarmCommand {
    param([string]$Shell = (Get-HookShell))
    return "`"$Shell`" -ExecutionPolicy Bypass -File `"$RepoScripts\keep-awake.ps1`" disarm *> `$null; if (`$LASTEXITCODE -ne 0) { exit 0 }"
}
function Install-Hook {
    $cmd = Get-HookCommand
    $disarm = Get-DisarmCommand
    foreach ($file in Get-HookTargets) {
        try {
            $j = if (Test-Path $file) { Get-Content $file -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
            if (-not $j.hooks) {
                $j = $j | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{}) -PassThru
            }
            foreach ($pair in @(@('UserPromptSubmit',$cmd), @('Stop',$disarm))) {
                $evt = $pair[0]; $hookCmd = $pair[1]
                $arr = $j.hooks.$evt
                if (-not $arr) {
                    $j.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue @() -Force
                    $arr = @()
                }
                # Idempotent: skip if our script's arm/disarm already present.
                $marker = if ($evt -eq 'UserPromptSubmit') { 'arm' } else { 'disarm' }
                $exists = $false
                foreach ($entry in $arr) {
                    if ($entry.command -and ($entry.command -like "*keep-awake.ps1*") -and ($entry.command -like "*$marker*")) { $exists = $true; break }
                }
                if (-not $exists) {
                    $newEntry = [PSCustomObject]@{ type = 'command'; command = $hookCmd }
                    $j.hooks.$evt = @($arr) + $newEntry
                }
            }
            $j | ConvertTo-Json -Depth 10 | Set-Content -Path $file -Encoding UTF8
            Write-Host "✓ hooks 已安装到 $file" -ForegroundColor Green
        } catch {
            Write-Host "⚠️  $file 钩子安装失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
function Uninstall-Hook {
    foreach ($file in Get-HookTargets) {
        try {
            if (-not (Test-Path $file)) { continue }
            $j = Get-Content $file -Raw | ConvertFrom-Json
            if (-not $j.hooks) { continue }
            foreach ($evt in @('UserPromptSubmit','Stop')) {
                $arr = $j.hooks.$evt
                if (-not $arr) { continue }
                $marker = if ($evt -eq 'UserPromptSubmit') { 'arm' } else { 'disarm' }
                $kept = @()
                foreach ($entry in $arr) {
                    $isOurs = $false
                    if ($entry.command -and ($entry.command -like '*keep-awake.ps1*') -and ($entry.command -like "*$marker*")) { $isOurs = $true }
                    # Also detect and remove the old nested shape left by earlier versions.
                    if ((-not $isOurs) -and $entry.hooks) {
                        $nestedKeep = @()
                        foreach ($h in $entry.hooks) {
                            if ($h.command -and ($h.command -like '*keep-awake.ps1*') -and ($h.command -like "*$marker*")) { $isOurs = $true; continue }
                            $nestedKeep += $h
                        }
                        if ($isOurs) {
                            # If the nested wrapper only held our hook, drop the whole wrapper.
                            if ($nestedKeep.Count -eq 0) { continue }
                            $entry | Add-Member -NotePropertyName hooks -NotePropertyValue $nestedKeep -Force
                        }
                    }
                    if (-not $isOurs) { $kept += $entry }
                }
                if ($kept.Count -gt 0) { $j.hooks.$evt = $kept }
                else { $j.hooks.PSObject.Properties.Remove($evt) }
            }
            $hasAny = $false
            foreach ($p in $j.hooks.PSObject.Properties) { $hasAny = $true; break }
            if (-not $hasAny) { $j.PSObject.Properties.Remove('hooks') }
            $j | ConvertTo-Json -Depth 10 | Set-Content -Path $file -Encoding UTF8
            Write-Host "✓ hooks 已从 $file 移除" -ForegroundColor Green
        } catch {
            Write-Host "⚠️  $file 钩子移除失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# ---- Scheduled task install/uninstall ---------------------------------------
function Invoke-BootCheck {
    # Startup self-check: if a strong state is left behind but the watcher is not
    # running, restore the power plan so we never stay stuck in no-sleep mode.
    if ((Test-Path $StrongFlag) -or (Test-Path $BackupFile)) {
        if (-not (Test-WatcherRunning)) {
            Write-Host "检测到 keep-awake 强防护状态残留且守护进程未运行，自动恢复电源计划…" -ForegroundColor Cyan
            $ok = Invoke-StrongOp -Op 'restore'
            if ($ok) {
                Write-Host "✓ 已自动恢复电源计划。" -ForegroundColor Green
                Remove-Item -Path $StrongFlag -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "⚠️ 自动恢复未成功，请手动运行: keep-awake.ps1 restore" -ForegroundColor Yellow
            }
            return
        }
    }
    Write-Host "Bootcheck OK" -ForegroundColor Gray
}

function Install-Task {
    # One-time UAC: register a HIGHEST-privilege task that runs strong-op.ps1,
    # plus a logon task that runs a boot self-check so we never leave the power
    # plan stuck if the daemon was killed before shutdown/reboot.
    if (Test-TaskRegistered) {
        Write-Host "✓ 计划任务 $TaskName 已存在，无需重复注册。" -ForegroundColor Green
        if (Test-TaskRegistered -Name $BootTaskName) { return }
    }
    Write-Host "注册最高权限计划任务 $TaskName 与开机自检 $BootTaskName（将弹一次 UAC）…" -ForegroundColor Cyan
    # Prefer PowerShell 7 so scripts run in the same environment we tested.
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $exe = if ($pwsh) { $pwsh.Source } else { 'powershell.exe' }

    # Use the ScheduledTasks module (built into Windows) instead of schtasks.exe
    # command-line quoting, which is fragile when paths contain spaces/quotes.
    # Build the temp script content in a here-string; arguments are pre-quoted.
    $strongArg = '-NonInteractive -ExecutionPolicy Bypass -File "' + $StrongOp + '"'
    $bootArg   = '-NoProfile -ExecutionPolicy Bypass -File "' + $KeepAwake + '" bootcheck'
    $tmpContent = @"
`$ErrorActionPreference = 'Stop'
Import-Module ScheduledTasks
`$user = if (`$env:USERDOMAIN) { "`$env:USERDOMAIN\`$env:USERNAME" } else { "`$env:USERNAME" }

# Strong-op task (on-demand, highest privilege)
`$strongAction = New-ScheduledTaskAction -Execute '$exe' -Argument '$strongArg'
`$principal = New-ScheduledTaskPrincipal -UserId `$user -RunLevel Highest
`$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel
`$task = New-ScheduledTask -Action `$strongAction -Principal `$principal -Settings `$settings
Register-ScheduledTask -TaskName '$TaskName' -InputObject `$task -Force | Out-Null

# Boot self-check task (run once at user logon)
`$bootAction = New-ScheduledTaskAction -Execute '$exe' -Argument '$bootArg'
`$trigger = New-ScheduledTaskTrigger -AtLogon -User `$user
`$bootTask = New-ScheduledTask -Action `$bootAction -Principal `$principal -Settings `$settings
Register-ScheduledTask -TaskName '$BootTaskName' -InputObject `$bootTask -Force | Out-Null

Write-Host "计划任务 $TaskName 与 $BootTaskName 已注册。" -ForegroundColor Green
"@
    $tmp = Join-Path $env:TEMP ("ka-register-" + [System.IO.Path]::GetRandomFileName() + ".ps1")
    Set-Content -Path $tmp -Value $tmpContent -Encoding UTF8

    try {
        $p = Start-Process -FilePath $exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($p.ExitCode -eq 0 -and (Test-TaskRegistered) -and (Test-TaskRegistered -Name $BootTaskName)) {
            Write-Host "✓ 已注册。此后 super/flex 的合盖防护免密生效，且登录时会自检。" -ForegroundColor Green
        } else {
            Write-Host "❌ 注册失败（退出码 $($p.ExitCode)）。" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ UAC 被取消或失败: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}
function Uninstall-Task {
    $any = $false
    foreach ($name in @($TaskName, $BootTaskName)) {
        if (-not (Test-TaskRegistered -Name $name)) {
            Write-Host "计划任务 $name 不存在。" -ForegroundColor Gray
            continue
        }
        $any = $true
        Write-Host "移除计划任务 $name…" -ForegroundColor Cyan
    }
    if (-not $any) { return }

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $exe = if ($pwsh) { $pwsh.Source } else { 'powershell.exe' }
    $tmp = Join-Path $env:TEMP ("ka-unregister-" + [System.IO.Path]::GetRandomFileName() + ".ps1")
    @"
`$ErrorActionPreference = 'Stop'
Import-Module ScheduledTasks
foreach (`$name in @('$TaskName', '$BootTaskName')) {
    try {
        Unregister-ScheduledTask -TaskName `$name -Confirm:`$false -ErrorAction Stop
        Write-Host "计划任务 `$name 已移除。" -ForegroundColor Green
    } catch {
        Write-Host "计划任务 `$name 移除失败或不存在。" -ForegroundColor Yellow
    }
}
"@ | Set-Content -Path $tmp -Encoding UTF8
    try {
        $p = Start-Process -FilePath $exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($p.ExitCode -eq 0) { Write-Host "✓ 已移除。" -ForegroundColor Green }
        else { Write-Host "❌ 移除失败（退出码 $($p.ExitCode)）。" -ForegroundColor Red }
    } catch {
        Write-Host "❌ UAC 被取消或失败: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}

# ---- Entry -------------------------------------------------------------------
$cmd = if ($Rest -and $Rest.Count -ge 1) { $Rest[0] } else { 'status' }
switch ($cmd) {
    'on'             { Invoke-On -Mode $Rest[1] }
    'off'            { Invoke-Off -Args ($Rest | Select-Object -Skip 1) }
    'status'         { Invoke-Status }
    ''               { Invoke-Status }
    'arm'            { Invoke-Arm }
    'disarm'         { Invoke-Disarm }
    'restore'        { Invoke-Restore }
    'install-task'   { Install-Task }
    'uninstall-task' { Uninstall-Task }
    'install-hook'   { Install-Hook }
    'uninstall-hook' { Uninstall-Hook }
    'bootcheck'      { Invoke-BootCheck }
    default {
        Write-Host "未知命令: $cmd" -ForegroundColor Red
        Write-Host "用法: keep-awake.ps1 on <super|flex|normal> | off [--sleep-now] | status | restore | arm | disarm | install-task | uninstall-task | install-hook | uninstall-hook | bootcheck"
        exit 1
    }
}
