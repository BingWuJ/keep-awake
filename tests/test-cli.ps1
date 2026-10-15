#!/usr/bin/env pwsh
# 在 TEMP 子进程执行真实 CLI；只替换电源/进程/启动器/等待等系统边界。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('keep-awake-cli-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$count = 0
$failures = [Collections.Generic.List[string]]::new()
function Assert-Case($name, [bool]$passed) {
  $script:count++
  if ($passed) { Write-Host "PASS $name" } else { $script:failures.Add($name); Write-Host "FAIL $name" -ForegroundColor Red }
}
$cases = @(
  @{ Name='status-empty'; Command='status'; Pid=''; Mode=''; State=''; Exit=0; Match='未开启' },
  @{ Name='status-foreign'; Command='status'; Pid='42002'; Mode='on'; State='holding-ac'; Exit=0; Match='未开启' },
  @{ Name='on-foreign'; Command='on'; Pid='42002'; Mode='on'; State='holding-ac'; StartState='holding-ac'; Exit=0; Match='ON：插电中'; Starts=1 },
  @{ Name='off-foreign'; Command='off'; Pid='42002'; Mode='on'; State='holding-ac'; Exit=0; Match='OFF：守护进程已停' },
  @{ Name='off-empty'; Command='off'; Pid=''; Mode=''; State=''; Exit=0; Match='OFF：守护进程已停' },
  @{ Name='unknown-command'; Command='super'; Exit=1; Match='未知命令' },
  @{ Name='on-unknown-power'; Command='on'; Power='Unknown'; Exit=1; Match='读不到电源状态'; Starts=0 },
  @{ Name='on-battery'; Command='on'; Power='Offline'; StartState='released-battery'; Exit=0; Match='未挡睡眠'; Starts=1 },
  @{ Name='on-empty-state'; Command='on'; Pid='42001'; Mode='on'; State=''; Running=$true; Exit=1; Match='未报告状态'; Starts=0 },
  @{ Name='on-stale-state'; Command='on'; State='holding-ac'; StartState='starting'; Exit=1; Match='未报告状态'; Starts=1 },
  @{ Name='on-idempotent'; Command='on'; Pid='42001'; State='holding-ac'; Running=$true; Exit=0; Match='ON：插电中'; Starts=0 },
  @{ Name='legacy-bad-json'; Command='off'; Backup='{broken'; Exit=1; Match='备份.*无法解析'; Elevation=$false },
  @{ Name='legacy-bad-scheme'; Command='off'; Backup='{"scheme":"x; Write-Output PWNED","settings":{}}'; Exit=1; Match='scheme 字段异常'; Elevation=$false },
  @{ Name='legacy-bad-ac'; Command='off'; Backup='{"scheme":"11111111-1111-1111-1111-111111111111","settings":{"LIDACTION":{"ac":"1; Write-Output PWNED","dc":1}}}'; Exit=1; Match='ac/dc 不是整数'; Elevation=$false },
  @{ Name='legacy-cancel-uac'; Command='off'; LegacyResult='{"old":"evidence"}'; Exit=1; Match='UAC 被取消或失败'; Elevation=$true },
  @{ Name='old-hooks-only'; Command='off'; Hooks=$true; Exit=0; Match='已从.*移除旧版'; Elevation=$false }
)
$driver = @'
$ErrorActionPreference = 'Stop'
$global:kaConfig = Get-Content -LiteralPath $env:KA_TEST_CONFIG -Raw | ConvertFrom-Json
$global:kaRunning = [bool]$global:kaConfig.Running
$global:kaStarts = 0
$global:kaKills = [Collections.Generic.List[int]]::new()
$global:kaElevation = $false
$global:kaClock = 0
$global:kaCompleted = $false
function Get-Date {
  param([string]$Format)
  $global:kaClock += 500
  $date = ([datetime]'2026-01-01T00:00:00').AddMilliseconds($global:kaClock)
  if ($Format) { return $date.ToString($Format) }
  return $date
}
function Get-Process {
  [CmdletBinding()] param([int]$Id)
  if ($Id -eq 42002 -or ($Id -eq 42001 -and $global:kaRunning)) { return [pscustomobject]@{ Id=$Id } }
  if ($ErrorActionPreference -eq 'Stop') { throw 'simulated process not found' }
}
function Get-CimInstance {
  [CmdletBinding()] param([string]$ClassName, [string]$Filter)
  if ($Filter -eq 'ProcessId=42002') { return [pscustomobject]@{ ProcessId=42002; CommandLine='foreign.exe' } }
  if ($Filter -eq 'ProcessId=42001' -and $global:kaRunning) { return [pscustomobject]@{ ProcessId=42001; CommandLine='pwsh.exe -File awake-watcher.ps1' } }
}
function Stop-Process {
  [CmdletBinding()] param([int]$Id, [switch]$Force)
  $global:kaKills.Add($Id)
  throw 'No physical process termination permitted in tests'
}
function Start-Process {
  [CmdletBinding()] param($FilePath, $ArgumentList, $Verb, [switch]$Wait, [switch]$PassThru)
  $global:kaElevation = $true
  throw 'simulated UAC cancellation'
}
function schtasks { $global:LASTEXITCODE = 1 }
function Start-Sleep { param([int]$Milliseconds, [int]$Seconds) }
$global:LASTEXITCODE = 0
$thrown = $null
try { $output = (& (Join-Path $PSScriptRoot 'keep-awake.ps1') $global:kaConfig.Command *>&1 | Out-String) }
catch { $thrown = $_.Exception.Message; $output = $thrown }
$exitCode = if ($global:kaCompleted -and -not $thrown) { 0 } else { 1 }
$state = Join-Path $env:USERPROFILE '.keep-awake'
@{
  ExitCode=$exitCode; Output=$output; Starts=$global:kaStarts; Kills=@($global:kaKills)
  Elevation=$global:kaElevation; BackupExists=Test-Path (Join-Path $state 'power-backup.json')
  LegacyResult=if (Test-Path (Join-Path $state 'strong-result.json')) { Get-Content (Join-Path $state 'strong-result.json') -Raw } else { '' }
  StaleExists=Test-Path (Join-Path $state 'strong-result.json.stale')
  PiExists=Test-Path (Join-Path $env:USERPROFILE '.pi')
  ClaudeExists=Test-Path (Join-Path $env:USERPROFILE '.claude')
  Hooks=if (Test-Path (Join-Path $env:USERPROFILE '.pi/agent/settings.json')) { Get-Content (Join-Path $env:USERPROFILE '.pi/agent/settings.json') -Raw } else { '' }
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $global:kaConfig.Result -Encoding utf8
'@
try {
  $source = Get-Content -LiteralPath (Join-Path $repo 'scripts/keep-awake.ps1') -Raw
  $tokens = $null; $parseErrors = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors.Count) { throw 'CLI 语法错误' }
  $replacements = @{
    'Get-PowerLine' = 'function Get-PowerLine { if ($global:kaConfig.Power) { return $global:kaConfig.Power }; return "Online" }'
    'Start-Watcher' = @'
function Start-Watcher {
  $global:kaStarts++
  $global:kaRunning = $true
  Set-Content -LiteralPath $PidFile -Value '42001'
  Set-Content -LiteralPath $StateOut -Value $global:kaConfig.StartState
}
'@
  }
  $nodes = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Get-PowerLine','Start-Watcher') }, $true))
  if ($nodes.Count -ne 2) { throw '无法准确隔离 CLI 系统边界，停止' }
  foreach ($node in ($nodes | Sort-Object { $_.Extent.StartOffset } -Descending)) {
    $source = $source.Substring(0,$node.Extent.StartOffset) + $replacements[$node.Name] + $source.Substring($node.Extent.EndOffset)
  }
  $source += "`n`$global:kaCompleted = `$true`n"
  foreach ($case in $cases) {
    $dir = Join-Path $root $case.Name
    $homeDir = Join-Path $dir 'home'
    $state = Join-Path $homeDir '.keep-awake'
    $null = New-Item -ItemType Directory -Path $state -Force
    foreach ($pair in @(@('Pid','awake.pid'),@('Mode','mode'),@('State','watcher-state'),@('Backup','power-backup.json'),@('LegacyResult','strong-result.json'))) {
      if ($case.ContainsKey($pair[0])) {
        $path = Join-Path $state $pair[1]
        if ([string]::IsNullOrEmpty([string]$case[$pair[0]])) { [IO.File]::WriteAllBytes($path, [byte[]]@()) }
        else { Set-Content -LiteralPath $path -Value $case[$pair[0]] -NoNewline -Encoding utf8BOM }
      }
    }
    if ($case.Hooks) {
      $settingsDir = Join-Path $homeDir '.pi/agent'
      $null = New-Item -ItemType Directory -Path $settingsDir -Force
      $hooks = '{"theme":"keep","hooks":{"UserPromptSubmit":[{"command":"pwsh keep-awake.ps1 arm"},{"command":"pwsh keep-awake.ps1 disarm"},{"command":"other.exe"}],"Stop":[{"command":"pwsh keep-awake.ps1 disarm"},{"command":"other-stop.exe"}]}}'
      Set-Content -LiteralPath (Join-Path $settingsDir 'settings.json') -Value $hooks -Encoding utf8BOM
    }
    Set-Content -LiteralPath (Join-Path $dir 'keep-awake.ps1') -Value $source -Encoding utf8BOM
    Set-Content -LiteralPath (Join-Path $dir 'run.ps1') -Value $driver -Encoding utf8BOM
    $case.Result = Join-Path $dir 'result.json'
    $config = Join-Path $dir 'config.json'
    $case | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding utf8
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh.exe'; $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($arg in @('-NoProfile','-NonInteractive','-File',(Join-Path $dir 'run.ps1'))) { $start.ArgumentList.Add($arg) }
    $start.Environment['USERPROFILE'] = $homeDir; $start.Environment['KA_TEST_CONFIG'] = $config
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
      $null = $process.Start(); $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
      if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw "超时: $($case.Name)" }
      if ($process.ExitCode -ne 0) { throw "$($case.Name): $($stderr.GetAwaiter().GetResult()) $($stdout.GetAwaiter().GetResult())" }
    } finally { $process.Dispose() }
    $result = Get-Content -LiteralPath $case.Result -Raw | ConvertFrom-Json
    Assert-Case "$($case.Name): 退出与消息" (($result.ExitCode -eq $case.Exit) -and $result.Output -match $case.Match -and $result.Output -notmatch 'null-valued|null 值|PWNED')
    Assert-Case "$($case.Name): 不杀无关进程" ($result.Kills.Count -eq 0)
    if ($case.ContainsKey('Starts')) { Assert-Case "$($case.Name): 启动次数" ($result.Starts -eq $case.Starts) }
    if ($case.ContainsKey('Elevation')) { Assert-Case "$($case.Name): 提权边界" ($result.Elevation -eq $case.Elevation) }
    if ($case.Backup) { Assert-Case "$($case.Name): 失败保留备份" $result.BackupExists }
    if ($case.LegacyResult) { Assert-Case "$($case.Name): 取消后还原结果证据" (($result.LegacyResult.Trim() -eq $case.LegacyResult) -and -not $result.StaleExists) }
    if ($case.Hooks) {
      $hooks = $result.Hooks | ConvertFrom-Json
      Assert-Case '旧钩子仅删目标，保留 disarm 非匹配与其他配置' (($hooks.theme -eq 'keep') -and $hooks.hooks.UserPromptSubmit.Count -eq 2 -and $hooks.hooks.UserPromptSubmit[0].command -match 'disarm' -and $hooks.hooks.Stop.Count -eq 1 -and $hooks.hooks.Stop[0].command -eq 'other-stop.exe')
    } else { Assert-Case "$($case.Name): 不创建 settings 目录" (-not $result.PiExists -and -not $result.ClaudeExists) }
  }
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
Write-Host "$count assertions; $($failures.Count) failed (system boundaries mocked)"
if ($failures.Count) { exit 1 }
exit 0
