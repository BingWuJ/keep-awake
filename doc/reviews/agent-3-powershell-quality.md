# Agent 3 · PowerShell 代码质量审查报告

**审查日期**: 2026-06-22
**被审代码**: `keep-awake/` 主分支（D 环节完成后）
**初始评分**: 7 / 10

---

## P0 · 致命

（本角度未发现独立 P0；P0 问题见 Agent 1，需在 A 环节清零。）

---

## P1 · 重要

### P1-1 · `Start-Process -ArgumentList` 中路径被重复加引号

- **文件**: `keep-awake.ps1:90`、`keep-awake.ps1:397`、`keep-awake.ps1:425`
- **问题**: `Start-Process` 的 `-ArgumentList` 已经会对含空格的元素自动加引号；代码里又手动包了一层 `"`...`"`。当仓库路径含空格时，命令行会出现双重引号或空引号，导致 `pwsh` 找不到脚本文件。
- **修复**: 将路径变量直接传入数组，例如 `'`-File',$Watcher`。

### P1-2 · `Stop-ScheduledTask` 权限与异常处理不足

- **文件**: `keep-awake.ps1:120`
- **问题**: 对 `RunLevel Highest` 的任务调用 `Stop-ScheduledTask` 普通用户可能无权执行；当前只是 `-ErrorAction SilentlyContinue`，没有记录或回退逻辑。
- **修复**: 捕获具体异常并在日志中记录；结合请求 ID 机制使并发结果可区分。

### P1-3 · 计划任务 `MultipleInstances Parallel` 与无请求 ID 的结果文件

- **文件**: `keep-awake.ps1:388`
- **问题**: 并行实例会读写同一 `strong-cmd` / `strong-result.json`，父进程无法判断结果来自哪一次触发。
- **修复**: 在命令文件中加入唯一请求 ID，结果文件回写相同 ID；父进程校验 ID 匹配。

### P1-4 · Global Mutex 创建失败降级为无单实例保护

- **文件**: `awake-watcher.ps1:76`
- **问题**: `Global\` 命名空间对非管理员用户常不可用，捕获后 `$Mutex = $null`，单实例保护完全失效。
- **修复**: Global 失败后回退 `Local\keep-awake-watcher`。

### P1-5 · `powercfg` 调用未检查返回码

- **文件**: `strong-op.ps1`（多处）
- **问题**: `Set-SettingValue` 与 `/setactive` 均未检查 `$LASTEXITCODE` 或 stderr，失败时仍可能写入 `status=ok`。
- **修复**: 对关键调用捕获输出和返回码，失败时 `Write-Result` 返回 `error`。

### P1-6 · `info` 文件不是 JSON

- **文件**: `keep-awake.ps1:167`
- **问题**: 同 Agent 2 P1-1。非结构化文本不利于状态解析和后续扩展。
- **修复**: 改用 `ConvertTo-Json`。

### P1-7 · 守护进程先睡后检查 stop 哨兵

- **文件**: `awake-watcher.ps1`
- **问题**: 同 Agent 2 P1-4。先 `Start-Sleep` 后检查哨兵，停止延迟最大 5s。
- **修复**: 交换循环顺序。

### P1-8 · `install.ps1` 存在未使用的 `Test-Command` 函数

- **文件**: `install.ps1`
- **问题**: 函数定义后未被调用，产生死代码。
- **修复**: 删除或实际使用它来决定 `$shell`。

---

## P2 · 建议

- `Write-Host` 遍布全项目，考虑在可被其他脚本消费的函数中改用 `Write-Output` / 返回对象。
- `statusline.ps1` 的 BOM 剥离正则不够直观，可用 `[System.Text.Encoding]::UTF8.GetBytes` / `GetPreamble` 判断。
- `Install-Hook` 对 `settings.json` 使用 `ConvertFrom-Json`，不支持 JSONC 注释。
- 缺少 Pester / PSScriptAnalyzer 的自动化测试与静态检查。
- `strong-op.ps1` 的 `Write-Log` 中 `ERROR` 级同时写日志和控制台，但非 ERROR 级不写入控制台，调试时可见性一般。

---

## 复评记录（A 环节后回填）

| 项目 | 状态 | 备注 |
|---|---|---|
| P1-1 | 待修复 | |
| P1-2 | 待修复 | |
| P1-3 | 待修复 | |
| P1-4 | 待修复 | |
| P1-5 | 待修复 | |
| P1-6 | 待修复 | |
| P1-7 | 待修复 | |
| P1-8 | 待修复 | |
