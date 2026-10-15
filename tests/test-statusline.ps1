#!/usr/bin/env pwsh
# 不关闭 stdin 的状态行隔离测试，核验单行输出、空文件与 PID 归属且无文件写入。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path ([IO.Path]::GetTempPath()) ('keep-awake-statusline-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$count = 0
$failures = [Collections.Generic.List[string]]::new()
function Assert-Case($name, [bool]$passed) {
  $script:count++
  if ($passed) { Write-Host "PASS $name" } else { $script:failures.Add($name); Write-Host "FAIL $name" -ForegroundColor Red }
}
function Get-Snapshot($dir) {
  # 排除 pwsh 宿主自己的启动缓存；只核对组件承诺不写的状态及客户端目录。
  $entries = foreach ($name in @('.keep-awake','.pi','.claude')) {
    $path = Join-Path $dir $name
    if (Test-Path -LiteralPath $path) {
      $path
      Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
      }
    }
  }
  return (@($entries) -join '|')
}
$cases = @(
  @{ Name='no-directory'; Match='^○ Sleep OK$' },
  @{ Name='empty-mode'; Mode=''; Match='^○ Sleep OK$' },
  @{ Name='off-mode'; Mode='off'; Match='^○ Sleep OK$' },
  @{ Name='missing-pid'; Mode='on'; Match='^⚠.*stale' },
  @{ Name='empty-pid'; Mode='on'; Pid=''; Match='^⚠.*stale' },
  @{ Name='invalid-pid'; Mode='on'; Pid='not-a-pid'; Match='^⚠.*stale' },
  @{ Name='foreign-pid'; Mode='on'; Pid='42002'; State='holding-ac'; Match='^⚠.*stale' },
  @{ Name='empty-state'; Mode='on'; Pid='42001'; State=''; Match='^⚠' },
  @{ Name='missing-state'; Mode='on'; Pid='42001'; Match='^⚠' },
  @{ Name='starting'; Mode='on'; Pid='42001'; State='starting'; Match='^⚠' },
  @{ Name='holding'; Mode='on'; Pid='42001'; State='holding-ac'; Match='^● Awake \(AC\)$' },
  @{ Name='battery'; Mode='on'; Pid='42001'; State='released-battery'; Match='^◐ Awake idle \(battery - not held\)$' },
  @{ Name='error'; Mode='on'; Pid='42001'; State='error-power-unknown'; Match='^⚠ Awake error' }
)
$driver = @'
function Get-CimInstance {
  [CmdletBinding()] param([string]$ClassName, [string]$Filter)
  if ($Filter -eq 'ProcessId=42001') { return [pscustomobject]@{ CommandLine='pwsh -File awake-watcher.ps1' } }
  return [pscustomobject]@{ CommandLine='unrelated.exe' }
}
& (Join-Path $PSScriptRoot 'statusline.ps1')
'@
try {
  foreach ($case in $cases) {
    $dir = Join-Path $root $case.Name
    $homeDir = Join-Path $dir 'home'
    $null = New-Item -ItemType Directory -Path $homeDir -Force
    if ($case.ContainsKey('Mode')) {
      $state = Join-Path $homeDir '.keep-awake'
      $null = New-Item -ItemType Directory -Path $state -Force
      foreach ($pair in @(@('Mode','mode'),@('Pid','awake.pid'),@('State','watcher-state'))) {
        if ($case.ContainsKey($pair[0])) {
          $path = Join-Path $state $pair[1]
          if ([string]::IsNullOrEmpty([string]$case[$pair[0]])) { [IO.File]::WriteAllBytes($path, [byte[]]@()) }
          else { Set-Content -LiteralPath $path -Value $case[$pair[0]] -Encoding utf8BOM -NoNewline }
        }
      }
    }
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/statusline.ps1') -Destination $dir
    Set-Content -LiteralPath (Join-Path $dir 'run.ps1') -Value $driver -Encoding utf8BOM
    $before = Get-Snapshot $homeDir
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh.exe'; $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true; $start.RedirectStandardInput = $true
    foreach ($arg in @('-NoProfile','-NonInteractive','-File',(Join-Path $dir 'run.ps1'))) { $start.ArgumentList.Add($arg) }
    $start.Environment['USERPROFILE'] = $homeDir
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
      $null = $process.Start()
      $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
      # 故意不关闭管道；若脚本读 stdin 到 EOF，会触发超时而非假通过。
      $process.StandardInput.WriteLine('{"unrelated":"stdin ignored"}')
      $process.StandardInput.Flush()
      $exited = $process.WaitForExit(10000)
      if (-not $exited) { $process.Kill($true); $process.WaitForExit() }
      $out = $stdout.GetAwaiter().GetResult()
      $err = $stderr.GetAwaiter().GetResult()
      $lines = @($out.TrimEnd("`r", "`n") -split '\r?\n')
      Assert-Case "$($case.Name): 不读 stdin、单行且状态诚实" ($exited -and $process.ExitCode -eq 0 -and $lines.Count -eq 1 -and $lines[0] -match $case.Match -and [string]::IsNullOrWhiteSpace($err))
    } finally { $process.Dispose() }
    $after = Get-Snapshot $homeDir
    Assert-Case "$($case.Name): 状态文件不变" ($after -ceq $before)
  }
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
Write-Host "$count assertions; $($failures.Count) failed (process ownership mocked)"
if ($failures.Count) { exit 1 }
exit 0
