#!/usr/bin/env pwsh
# 隔离回归：只运行 TEMP 副本，替换 off 和任务查询；不触碰真实状态与计划任务。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('keep-awake-install-tests-' + [guid]::NewGuid().ToString('N'))
$failures = [Collections.Generic.List[string]]::new()
$count = 0

function Assert-Case($name, [bool]$passed) {
  $script:count++
  if ($passed) { Write-Host "PASS $name" } else {
    $script:failures.Add($name)
    Write-Host "FAIL $name" -ForegroundColor Red
  }
}

function New-Case($name, [int]$offExit = 0, [bool]$tasksExist = $false) {
  $dir = Join-Path $root $name
  $homeDir = Join-Path $dir 'home'
  $state = Join-Path $homeDir '.keep-awake'
  $scripts = Join-Path $dir 'scripts'
  $bin = Join-Path $dir 'bin'
  $null = New-Item -ItemType Directory -Path $state, $scripts, $bin -Force
  Copy-Item -LiteralPath (Join-Path $repo 'uninstall.ps1') -Destination $dir
  Copy-Item -LiteralPath (Join-Path $repo 'install.ps1') -Destination $dir
  Set-Content -LiteralPath (Join-Path $scripts 'keep-awake.ps1') -Value "exit $offExit" -Encoding utf8BOM
  Set-Content -LiteralPath (Join-Path $scripts 'awake-watcher.ps1') -Value '# syntax stub' -Encoding utf8BOM
  Set-Content -LiteralPath (Join-Path $scripts 'statusline.ps1') -Value '# syntax stub' -Encoding utf8BOM
  $taskExit = if ($tasksExist) { 0 } else { 1 }
  Set-Content -LiteralPath (Join-Path $bin 'schtasks.ps1') -Value "`$global:LASTEXITCODE = $taskExit" -Encoding utf8BOM
  Set-Content -LiteralPath (Join-Path $state 'mode') -Value 'on' -Encoding utf8BOM
  Set-Content -LiteralPath (Join-Path $state 'power-backup.json') -Value '{"test":"preserve"}' -Encoding utf8BOM
  return @{ Dir = $dir; HomeDir = $homeDir; State = $state; Bin = $bin }
}

function Invoke-Case($case, $scriptName = 'uninstall.ps1') {
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = Join-Path $PSHOME 'pwsh.exe'
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($arg in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $case.Dir $scriptName))) {
    $start.ArgumentList.Add($arg)
  }
  $start.Environment['USERPROFILE'] = $case.HomeDir
  $start.Environment['PATH'] = $case.Bin + [IO.Path]::PathSeparator + $env:PATH
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $start
  try {
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
      $process.Kill($true)
      throw '测试子进程超时'
    }
    return @{ ExitCode = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
  } finally { $process.Dispose() }
}

try {
  $case = New-Case 'off-failure' 1
  $result = Invoke-Case $case
  Assert-Case 'off 失败必须 exit 1' ($result.ExitCode -eq 1)
  Assert-Case 'off 失败保留备份且不宣称卸载完成' ((Test-Path (Join-Path $case.State 'power-backup.json')) -and $result.Output -notmatch '✅ keep-awake 已卸载')

  $case = New-Case 'missing-off'
  Remove-Item -LiteralPath (Join-Path $case.Dir 'scripts/keep-awake.ps1')
  $result = Invoke-Case $case
  Assert-Case 'off 脚本缺失必须 exit 1 且保留状态' (($result.ExitCode -eq 1) -and (Test-Path $case.State) -and $result.Output -notmatch '✅ keep-awake 已卸载')

  $case = New-Case 'remaining-tasks' 0 $true
  $result = Invoke-Case $case
  Assert-Case '任务残留 exit 1 并提示管理员' (($result.ExitCode -eq 1) -and $result.Output -match '管理员')
  Assert-Case '任务残留必须保留备份' (Test-Path (Join-Path $case.State 'power-backup.json'))

  $case = New-Case 'locked-state'
  $locked = [IO.File]::Open((Join-Path $case.State 'mode'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try { $result = Invoke-Case $case } finally { $locked.Dispose() }
  Assert-Case '目录删不掉必须 exit 1 不报成功' (($result.ExitCode -eq 1) -and (Test-Path $case.State) -and $result.Output -notmatch '✅ keep-awake 已卸载')

  $case = New-Case 'real-off-corrupt-backup'
  Copy-Item -LiteralPath (Join-Path $repo 'scripts/keep-awake.ps1') -Destination (Join-Path $case.Dir 'scripts/keep-awake.ps1') -Force
  Set-Content -LiteralPath (Join-Path $case.State 'power-backup.json') -Value '{broken' -Encoding utf8BOM
  $result = Invoke-Case $case
  Assert-Case '真实 off 备份损坏时卸载 exit 1' ($result.ExitCode -eq 1)
  Assert-Case '真实清理失败保留原始备份且不报成功' ((Test-Path (Join-Path $case.State 'power-backup.json')) -and $result.Output -notmatch '✅ keep-awake 已卸载')

  $case = New-Case 'success'
  $result = Invoke-Case $case
  Assert-Case '成功卸载 exit 0 且删状态目录' (($result.ExitCode -eq 0) -and -not (Test-Path $case.State) -and $result.Output -match '✅ keep-awake 已卸载')
  $result = Invoke-Case $case
  Assert-Case '重复卸载安全幂等' (($result.ExitCode -eq 0) -and -not (Test-Path $case.State))

  $case = New-Case 'install-success'
  Remove-Item -LiteralPath $case.State -Recurse -Force
  $result = Invoke-Case $case 'install.ps1'
  Assert-Case 'install 成功不创建状态目录' (($result.ExitCode -eq 0) -and -not (Test-Path $case.State))

  $case = New-Case 'install-missing'
  Remove-Item -LiteralPath (Join-Path $case.Dir 'scripts/awake-watcher.ps1')
  $result = Invoke-Case $case 'install.ps1'
  Assert-Case 'install 核心脚本缺失 exit 1' ($result.ExitCode -eq 1)

  $case = New-Case 'install-bad-syntax'
  Set-Content -LiteralPath (Join-Path $case.Dir 'scripts/statusline.ps1') -Value 'function {' -Encoding utf8BOM
  $result = Invoke-Case $case 'install.ps1'
  Assert-Case 'install 语法错误 exit 1' ($result.ExitCode -eq 1)
} finally {
  if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Host "$count assertions; $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
