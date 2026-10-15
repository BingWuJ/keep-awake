#!/usr/bin/env pwsh
# install.ps1 - Setup for keep-awake (Windows), post-contract edition.
#
# The new contract needs NO admin rights, NO scheduled task, NO hooks, NO power plan
# changes. Installation is therefore only: verify the scripts parse, detect leftovers of
# the OLD super/flex design, and print usage.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeepAwake  = Join-Path $RepoDir 'scripts\keep-awake.ps1'
$Watcher    = Join-Path $RepoDir 'scripts\awake-watcher.ps1'
$StatusLine = Join-Path $RepoDir 'scripts\statusline.ps1'

# ---- Syntax check ------------------------------------------------------------
Write-Host "→ 检查核心脚本语法…" -ForegroundColor Cyan
foreach ($f in @($KeepAwake, $Watcher, $StatusLine)) {
    if (-not (Test-Path $f)) { throw "脚本未找到: $f" }
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    if ($errs.Count -gt 0) { throw "$f 语法错误: $($errs[0].Message)" }
}
Write-Host "✅ 语法检查通过。" -ForegroundColor Green

# ---- Detect leftovers of the OLD design --------------------------------------
$state = Join-Path $env:USERPROFILE '.keep-awake'
$legacy = @()
foreach ($t in @('keep-awake-strong','keep-awake-bootcheck')) {
    $null = schtasks /query /tn $t 2>$null
    if ($LASTEXITCODE -eq 0) { $legacy += "计划任务 $t" }
}
foreach ($f in @('power-backup.json','strong','strong-cmd','strong-result.json')) {
    if (Test-Path (Join-Path $state $f)) { $legacy += $f }
}
foreach ($s in @((Join-Path $env:USERPROFILE '.pi\agent\settings.json'), (Join-Path $env:USERPROFILE '.claude\settings.json'))) {
    if ((Test-Path $s) -and ((Get-Content $s -Raw) -like '*keep-awake.ps1*')) { $legacy += "钩子: $s" }
}
if ($legacy.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠ 检测到旧版 keep-awake 残留: $($legacy -join ', ')" -ForegroundColor Yellow
    Write-Host "  运行 off 或 uninstall.ps1 可清理（仅此时才会请求一次 UAC）。" -ForegroundColor Yellow
}

# ---- Usage hints ---------------------------------------------------------------
Write-Host ""
Write-Host "✅ keep-awake 就绪。无需管理员、不注册任何任务、不改电源计划。" -ForegroundColor Green
Write-Host ""
Write-Host "常用命令:" -ForegroundColor Cyan
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" on      # 插电时挡住系统空闲睡眠；屏幕可自行变黑" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" status  # 查看状态" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass -File `"$KeepAwake`" off     # 停止，恢复正常睡眠" -ForegroundColor White
Write-Host ""
Write-Host "说明: 用电池时不挡睡眠；合盖/电源键/电源计划从不修改；重启后需重新 on。" -ForegroundColor Gray
Write-Host "卸载: pwsh -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $RepoDir 'uninstall.ps1')`"" -ForegroundColor Gray
