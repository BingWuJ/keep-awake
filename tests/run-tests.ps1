#!/usr/bin/env pwsh
# 串行运行有界回归；测试夹具全部使用 TEMP 用户及模拟系统边界，不接管真实 watcher。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
foreach ($script in @(Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -File) + @(Get-ChildItem -LiteralPath (Join-Path $repo 'scripts'), $PSScriptRoot -Filter '*.ps1' -File)) {
  $errors = $null
  $null = [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$errors)
  if ($errors.Count) { throw "语法错误: $($script.FullName): $($errors[0].Message)" }
  $bytes = [IO.File]::ReadAllBytes($script.FullName)
  if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw "不是 UTF-8 BOM: $($script.FullName)" }
}
foreach ($name in @('test-install-uninstall.ps1','test-watcher.ps1','test-cli.ps1','test-statusline.ps1')) {
  Write-Host "=== $name ===" -ForegroundColor Cyan
  & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot $name)
  if ($LASTEXITCODE -ne 0) { throw "回归失败: $name (exit $LASTEXITCODE)" }
}
foreach ($name in @('README.md','README.en.md','SKILL.md','QUICKSTART.md')) {
  $text = Get-Content -LiteralPath (Join-Path $repo $name) -Raw
  foreach ($match in [regex]::Matches($text, '(?s)```json\s*(.*?)```')) {
    $null = $match.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
  }
  foreach ($match in [regex]::Matches($text, '\]\(([^)]+)\)')) {
    $target = ($match.Groups[1].Value -split '#')[0]
    if ($target -and $target -notmatch '^https?://' -and -not (Test-Path -LiteralPath (Join-Path $repo $target))) { throw "失效链接: $name -> $target" }
  }
}
Write-Host 'ALL SUITES PASSED; JSON/links/syntax/BOM checked. Physical power/UAC behavior is not certified.' -ForegroundColor Green
exit 0
