#!/usr/bin/env pwsh
# uninstall.ps1 - Remove keep-awake (Windows) and any leftovers of the old design.
#
# Steps: run 'off' (stops the daemon; cleans legacy tasks / power backup / hooks - UAC is
# requested only when such old leftovers exist), then verify nothing is left, then delete
# the state directory.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeepAwake = Join-Path $RepoDir 'scripts\keep-awake.ps1'

if (-not (Test-Path -LiteralPath $KeepAwake -PathType Leaf)) {
    Write-Host "⚠ 未找到 $KeepAwake，无法确认守护进程与旧版残留已清理；保留状态目录。请恢复脚本后重试。" -ForegroundColor Yellow
    exit 1
}

Write-Host "→ 停止 keep-awake 并清理…" -ForegroundColor Cyan
try {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $KeepAwake off
    if ($LASTEXITCODE -ne 0) { throw "off 退出码为 $LASTEXITCODE" }
} catch {
    Write-Host "⚠ off 失败：$($_.Exception.Message)。未继续删除状态目录，请排除错误后重试。" -ForegroundColor Yellow
    exit 1
}

# ---- Verify legacy tasks are gone -------------------------------------------
$leftover = @()
foreach ($t in @('keep-awake-strong','keep-awake-bootcheck')) {
    $null = schtasks /query /tn $t 2>$null
    if ($LASTEXITCODE -eq 0) { $leftover += "计划任务 $t" }
}

if ($leftover.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠ 以下旧版计划任务未能删除（需要管理员权限）: $($leftover -join ', ')" -ForegroundColor Yellow
    Write-Host "  已保留状态目录与备份，请以管理员身份再次运行本脚本。" -ForegroundColor Yellow
    exit 1
}

# ---- Remove the state directory only after cleanup and task verification ------
$state = Join-Path $env:USERPROFILE '.keep-awake'
try {
    if (Test-Path -LiteralPath $state) {
        Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $state) { throw "状态目录仍存在: $state" }
} catch {
    Write-Host "⚠ 状态目录清理失败：$($_.Exception.Message)。卸载未完成，请排除占用或权限问题后重试。" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "✅ keep-awake 已卸载：守护进程、状态目录、旧版任务与备份均已清理。" -ForegroundColor Green
