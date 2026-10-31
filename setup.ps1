#!/usr/bin/env pwsh
# setup.ps1 - one-shot installer for keep-awake (Windows 11 + PowerShell 7).
#
# Human:  irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex
# Agent:  $env:KEEP_AWAKE_AGENT=1; irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex
#
# It downloads this repository into one fixed folder and runs install.ps1 there.
# No admin, no scheduled task, no registry writes, no PATH edits, no hooks.

[CmdletBinding()]
param(
    [string]$Dir,
    [switch]$Agent
)

$ErrorActionPreference = 'Stop'

$RepoZip  = 'https://codeload.github.com/BingWuJ/keep-awake/zip/refs/heads/main'
$RepoGit  = 'https://github.com/BingWuJ/keep-awake.git'
$isAgent  = $Agent -or ($env:KEEP_AWAKE_AGENT -eq '1')

$dir = if ($Dir) { $Dir }
       elseif ($env:KEEP_AWAKE_DIR) { $env:KEEP_AWAKE_DIR }
       else { Join-Path $env:LOCALAPPDATA 'Programs\keep-awake' }

function Say([string]$Message, [string]$Color = 'Gray') {
    if (-not $isAgent) { Write-Host $Message -ForegroundColor $Color }
}

$entry = Join-Path $dir 'scripts\keep-awake.ps1'

Say "→ 安装 keep-awake 到 $dir" Cyan

if (Test-Path $entry) {
    if (Test-Path (Join-Path $dir '.git')) {
        Say '→ 已安装，尝试更新到最新版…' Cyan
        git -C $dir pull --ff-only --quiet
        if ($LASTEXITCODE -ne 0) { Say '⚠ git pull 失败，继续使用现有副本。' Yellow }
    } else {
        Say '→ 目录里已有 keep-awake，跳过下载。' Cyan
    }
}
elseif ((Test-Path $dir) -and (Get-ChildItem $dir -Force | Select-Object -First 1)) {
    throw "目标目录非空且不是 keep-awake 安装目录：$dir。请换一个 -Dir，或先清空该目录。"
}
else {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        Say '→ git clone…' Cyan
        git clone --depth 1 --quiet $RepoGit $dir
        if ($LASTEXITCODE -ne 0) { throw "git clone 失败：$RepoGit" }
    }
    else {
        Say '→ 下载 zip（未检测到 git）…' Cyan
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("keep-awake-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $zip = Join-Path $tmp 'src.zip'
            Invoke-WebRequest -Uri $RepoZip -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Copy-Item (Join-Path $inner.FullName '*') $dir -Recurse -Force
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not (Test-Path $entry)) { throw "安装未完成：缺少 $entry" }

# 语法自检 + 旧版残留检测；Agent 模式下保持安静，除非出错。
$install = Join-Path $dir 'install.ps1'
if ($isAgent) { & $install *> $null } else { & $install }

if ($isAgent) {
    # 单行、ASCII，便于 Agent 解析；顺手清掉子进程留下的 LASTEXITCODE。
    # 不调用 exit：用户可能把这条命令粘进已有会话，退出整个会话太粗暴。
    $global:LASTEXITCODE = 0
    Write-Output "READY $dir"
}
else {
    Write-Host ''
    Write-Host "装好了。仓库在：$dir" -ForegroundColor Green
    Write-Host '长任务开始：' -NoNewline -ForegroundColor Cyan
    Write-Host "pwsh -NoProfile -File `"$entry`" on"
    Write-Host '结束记得：' -NoNewline -ForegroundColor Cyan
    Write-Host "pwsh -NoProfile -File `"$entry`" off"
    Write-Host '想装成 Agent 技能：把该目录放进 pi / Claude Code 的 skill 路径即可。' -ForegroundColor Gray
}
