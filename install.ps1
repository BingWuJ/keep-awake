#!/usr/bin/env pwsh
# install.ps1 - One-time setup for keep-awake (Windows).
#
# Registers the keep-awake-strong scheduled task (RunLevel=Highest) so that
# super/flex modes can toggle power-plan settings without a UAC prompt every
# time. The task creation itself triggers one UAC dialog; after that, the
# keep-awake.ps1 CLI never needs elevation again for strong-mode actions.
#
# Also offers to install the flex-mode hooks into pi/Claude Code settings.

[CmdletBinding()]
param(
    [switch]$TasksOnly
)

$ErrorActionPreference = 'Stop'

$RepoDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeepAwake = Join-Path $RepoDir 'scripts\keep-awake.ps1'
$Watcher   = Join-Path $RepoDir 'scripts\awake-watcher.ps1'
$StrongOp  = Join-Path $RepoDir 'scripts\strong-op.ps1'
$StatusLine= Join-Path $RepoDir 'scripts\statusline.ps1'

# ---- Pre-flight -------------------------------------------------------------
if (-not (Test-Path $KeepAwake)) { throw "脚本未找到: $KeepAwake" }

$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$shell = if ($pwsh) { $pwsh.Source } else {
    Write-Host "⚠️  未找到 PowerShell 7 (pwsh.exe)。将使用 Windows PowerShell 5。" -ForegroundColor Yellow
    'powershell.exe'
}

# Make sure the core scripts are executable-ish (PowerShell doesn't need +x,
# but we verify syntax so the user gets a clear error now instead of later).
Write-Host "→ 检查核心脚本语法…" -ForegroundColor Cyan
foreach ($f in @($KeepAwake, $Watcher, $StrongOp, $StatusLine)) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    if ($errs.Count -gt 0) { throw "$f 语法错误: $($errs[0].Message)" }
}

# ---- Register the HIGHEST-privilege scheduled task -------------------------
Write-Host ""
Write-Host "→ 注册免密提权计划任务 keep-awake-strong（会弹一次 UAC）…" -ForegroundColor Cyan
Write-Host "   这是为了让 super/flex 的合盖防护在以后使用时不再需要 UAC。" -ForegroundColor Gray

# keep-awake.ps1's install-task already handles the UAC-elevated schtasks call.
& $shell -NoProfile -ExecutionPolicy Bypass -File $KeepAwake install-task

# Verify it exists.
$task = schtasks /query /tn 'keep-awake-strong' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ 计划任务注册失败或未确认。super/flex 的合盖防护将无法自动生效。" -ForegroundColor Red
    Write-Host "   你可以稍后手动运行: $KeepAwake install-task" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ 计划任务 keep-awake-strong 已注册。" -ForegroundColor Green

# ---- Optional flex hooks ----------------------------------------------------
if (-not $TasksOnly) {
    Write-Host ""
    Write-Host "→ 安装 flex 模式 hooks（让 AI Agent 工作时自动唤醒、停下自动放开）…" -ForegroundColor Cyan
    & $shell -NoProfile -ExecutionPolicy Bypass -File $KeepAwake install-hook
}

# ---- Usage hints -------------------------------------------------------------
Write-Host ""
Write-Host "✅ keep-awake for Windows 安装完成。" -ForegroundColor Green
Write-Host ""
Write-Host "常用命令:" -ForegroundColor Cyan
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" on normal   # 开盖不睡，合盖睡" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" on flex     # 干活时全防护（含合盖）" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" on super    # 一直不睡（合盖/电池）直到 off" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" status" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" off" -ForegroundColor White
Write-Host ""
Write-Host "卸载:  pwsh -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $RepoDir 'uninstall.ps1')`"" -ForegroundColor Gray
