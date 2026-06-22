#!/usr/bin/env pwsh
# uninstall.ps1 - Completely remove keep-awake (Windows).
#
# Stops any active protection, removes the flex-mode hooks, deletes the
# keep-awake-strong scheduled task, and clears runtime state. Does NOT delete
# this repository; run it from the repo directory.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeepAwake = Join-Path $RepoDir 'scripts\keep-awake.ps1'

function Test-Command { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

if (-not (Test-Path $KeepAwake)) { throw "脚本未找到: $KeepAwake" }
$shell = if (Test-Command pwsh) { (Get-Command pwsh).Source } else { 'powershell.exe' }

$StateDir = Join-Path $env:USERPROFILE '.keep-awake'

Write-Host "→ 停止任何活动中的 keep-awake 防护并恢复电源计划…" -ForegroundColor Cyan
$offOutput = & $shell -NoProfile -ExecutionPolicy Bypass -File $KeepAwake off 2>&1
$offExit = $LASTEXITCODE
$offOutput | ForEach-Object { Write-Host "  $_" }
if ($offExit -ne 0) {
    Write-Host "❌ off 命令失败（退出码 $offExit）。卸载中止，保留状态目录以便排查/手动 restore。" -ForegroundColor Red
    exit 1
}

# Only remove backup/state after confirming strong-op has removed the backup itself.
if (Test-Path "$StateDir\power-backup.json") {
    Write-Host "⚠️  电源备份文件仍存在，说明恢复可能未成功。卸载中止。" -ForegroundColor Yellow
    Write-Host "   请手动检查电源计划，然后删除 $StateDir" -ForegroundColor Yellow
    exit 1
}

Write-Host "→ 移除 flex 模式 hooks…" -ForegroundColor Cyan
& $shell -NoProfile -ExecutionPolicy Bypass -File $KeepAwake uninstall-hook 2>&1 | ForEach-Object { Write-Host "  $_" }

Write-Host "→ 移除 keep-awake 计划任务（会弹一次 UAC）…" -ForegroundColor Cyan
& $shell -NoProfile -ExecutionPolicy Bypass -File $KeepAwake uninstall-task 2>&1 | ForEach-Object { Write-Host "  $_" }

if (Test-Path $StateDir) {
    Write-Host "→ 清理运行时状态目录…" -ForegroundColor Cyan
    Remove-Item -Path $StateDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "✅ keep-awake 已从本机移除。" -ForegroundColor Green
Write-Host "   如需重新安装，运行: install.ps1" -ForegroundColor Gray
Write-Host "   仓库目录 ($RepoDir) 不会被删除。" -ForegroundColor Gray
