#!/usr/bin/env pwsh
# 在隔离子进程中运行真实 watcher 控制流；仅替换电源、时钟、API 与互斥量名称。
# 不调用 Windows 防睡眠 API，不修改真实用户目录，不用虚拟测试宣称真机已验收。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('keep-awake-watcher-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$count = 0
$failures = [Collections.Generic.List[string]]::new()
function Assert-Case($name, [bool]$passed) {
  $script:count++
  if ($passed) { Write-Host "PASS $name" } else { $script:failures.Add($name); Write-Host "FAIL $name" -ForegroundColor Red }
}

$cases = @(
  @{ Name='steady-ac'; Power=@('Online') * 14; Fail=@(); Expected=@('holding-ac') * 14; HoldCount=2 },
  @{ Name='battery'; Power=@('Offline','Offline'); Fail=@(); Expected=@('released-battery','released-battery'); HoldCount=0 },
  @{ Name='unplug-replug'; Power=@('Online','Offline','Online'); Fail=@(); Expected=@('holding-ac','released-battery','holding-ac'); HoldCount=2 },
  @{ Name='unknown-recover'; Power=@('Online','Unknown','Online'); Fail=@(); Expected=@('holding-ac','error-power-unknown','holding-ac'); HoldCount=2 },
  @{ Name='initial-unknown'; Power=@('Unknown','Offline'); Fail=@(); Expected=@('error-power-unknown','released-battery'); HoldCount=0 },
  @{ Name='initial-api-failure'; Power=@('Online','Online'); Fail=@(1); Expected=@('error-power-unknown','holding-ac'); HoldCount=2 },
  @{ Name='reassert-failure'; Power=@('Online') * 14; Fail=@(2); Expected=(@('holding-ac') * 12 + @('error-power-unknown','holding-ac')); HoldCount=3 },
  @{ Name='release-failure-retry'; Power=@('Online','Offline','Offline'); Fail=@(2); Expected=@('holding-ac','error-power-unknown','released-battery'); HoldCount=1 },
  @{ Name='uncertain-retry'; Power=(@('Online') * 13 + @('Offline')); Fail=@(2,3); Expected=(@('holding-ac') * 12 + @('error-power-unknown','released-battery')); HoldCount=2 },
  @{ Name='publish-failure-retry'; Power=@('Online','Online'); Fail=@(); PublishFail=$true; PublishFailState='holding-ac'; Expected=@('starting','holding-ac'); HoldCount=1 },
  @{ Name='released-publish-retry'; Power=@('Online','Offline','Offline'); Fail=@(); PublishFail=$true; PublishFailState='released-battery'; Expected=@('holding-ac','holding-ac','released-battery'); HoldCount=1 },
  @{ Name='uncertain-still-failing'; Power=(@('Online') * 13 + @('Offline','Offline')); Fail=@(2,3,4); Expected=(@('holding-ac') * 12 + @('error-power-unknown','error-power-unknown','released-battery')); HoldCount=2 }
)

$prefix = @'
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $env:KA_TEST_CONFIG -Raw | ConvertFrom-Json
$global:kaRound = 0
$global:kaObserved = [Collections.Generic.List[string]]::new()
$global:kaPublishFailurePending = [bool]$config.PublishFail
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
namespace KeepAwake {
  public static class Native {
    [Flags] public enum EXECUTION_STATE : uint {
      ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 1, ES_DISPLAY_REQUIRED = 2
    }
    public static List<uint> Calls = new List<uint>();
    public static HashSet<int> Fail = new HashSet<int>();
    public static EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE flags) {
      Calls.Add((uint)flags);
      return Fail.Contains(Calls.Count) ? (EXECUTION_STATE)0 : EXECUTION_STATE.ES_CONTINUOUS;
    }
  }
}
"@
foreach ($index in $config.Fail) { $null = [KeepAwake.Native]::Fail.Add([int]$index) }
function Get-Date {
  param([string]$Format)
  $date = [datetime]'2026-01-01T00:00:00'
  $date = $date.AddSeconds(5 * $global:kaRound)
  if ($Format) { return $date.ToString($Format) }
  return $date
}
function Set-Content {
  [CmdletBinding()]
  param([string]$Path, $Value, [string]$Encoding)
  if ($global:kaPublishFailurePending -and $Path -like '*watcher-state' -and $Value -eq $config.PublishFailState) {
    $global:kaPublishFailurePending = $false
    throw 'simulated publish failure'
  }
  Microsoft.PowerShell.Management\Set-Content -LiteralPath $Path -Value $Value -Encoding $Encoding
}
function Start-Sleep {
  param([int]$Seconds)
  $statePath = Join-Path $env:USERPROFILE '.keep-awake/watcher-state'
  $state = if (Test-Path -LiteralPath $statePath) { [string](Get-Content -LiteralPath $statePath -Raw) } else { '' }
  $global:kaObserved.Add($state.Trim())
  $global:kaRound++
  if ($global:kaRound -ge $config.Power.Count) {
    Microsoft.PowerShell.Management\Set-Content -LiteralPath (Join-Path $env:USERPROFILE '.keep-awake/stop') -Value 'stop'
  }
}
& (Join-Path $PSScriptRoot 'awake-watcher.ps1') | Out-Null
$state = [string](Get-Content -LiteralPath (Join-Path $env:USERPROFILE '.keep-awake/watcher-state') -Raw -ErrorAction SilentlyContinue)
@{
  Observed = @($global:kaObserved)
  Calls = @([KeepAwake.Native]::Calls)
  FinalState = $state.Trim()
  PidExists = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.keep-awake/awake.pid')
} | ConvertTo-Json -Depth 5 | Microsoft.PowerShell.Management\Set-Content -LiteralPath $config.Result -Encoding utf8
'@

try {
  $sourcePath = Join-Path $repo 'scripts/awake-watcher.ps1'
  $source = Get-Content -LiteralPath $sourcePath -Raw
  $tokens = $null; $parseErrors = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors.Count) { throw 'watcher 源文件语法错误' }
  $powerFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PowerLine' }, $true)
  if (-not $powerFunction) { throw '未定位电源函数，拒绝运行未隔离脚本' }
  $powerStub = 'function Get-PowerLine { return [string]$config.Power[$global:kaRound] }'
  $source = $source.Substring(0, $powerFunction.Extent.StartOffset) + $powerStub + $source.Substring($powerFunction.Extent.EndOffset)
  if (-not $source.Contains("'Global\keep-awake-watcher'")) { throw '未定位互斥量，拒绝运行未隔离脚本' }

  foreach ($case in $cases) {
    $dir = Join-Path $root $case.Name
    $homeDir = Join-Path $dir 'home'
    $null = New-Item -ItemType Directory -Path $homeDir -Force
    $mutexName = 'Local\keep-awake-test-' + [guid]::NewGuid().ToString('N')
    $copy = $source.Replace("'Global\keep-awake-watcher'", "'$mutexName'")
    Set-Content -LiteralPath (Join-Path $dir 'awake-watcher.ps1') -Value $copy -Encoding utf8BOM
    Set-Content -LiteralPath (Join-Path $dir 'run.ps1') -Value $prefix -Encoding utf8BOM
    $case.Result = Join-Path $dir 'result.json'
    $configPath = Join-Path $dir 'config.json'
    $case | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding utf8
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh.exe'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($arg in @('-NoProfile','-NonInteractive','-File',(Join-Path $dir 'run.ps1'))) { $start.ArgumentList.Add($arg) }
    $start.Environment['USERPROFILE'] = $homeDir
    $start.Environment['KA_TEST_CONFIG'] = $configPath
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
      $null = $process.Start()
      $stdout = $process.StandardOutput.ReadToEndAsync()
      $stderr = $process.StandardError.ReadToEndAsync()
      if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw "子进程超时: $($case.Name)" }
      if ($process.ExitCode -ne 0) { throw "$($case.Name): $($stderr.GetAwaiter().GetResult()) $($stdout.GetAwaiter().GetResult())" }
    } finally { $process.Dispose() }
    $result = Get-Content -LiteralPath $case.Result -Raw | ConvertFrom-Json
    Assert-Case "$($case.Name): 状态序列" (($result.Observed -join ',') -ceq ($case.Expected -join ','))
    $holdCount = @($result.Calls | Where-Object { [uint32]$_ -eq 2147483649 }).Count
    Assert-Case "$($case.Name): API 请求次数" ($holdCount -eq $case.HoldCount)
    Assert-Case "$($case.Name): 从不请求 DISPLAY" (@($result.Calls | Where-Object { ([uint32]$_ -band 2) -ne 0 }).Count -eq 0)
    Assert-Case "$($case.Name): finally 清标志删 PID" (($result.FinalState -eq 'stopped') -and -not $result.PidExists -and [uint32]$result.Calls[-1] -eq 2147483648)
  }
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Host "$count assertions; $($failures.Count) failed (simulated IO, not physical power verification)"
if ($failures.Count) { exit 1 }
exit 0
