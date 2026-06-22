# Agent 2 · 原版功能语义对齐审查报告

**审查日期**: 2026-06-22
**被审代码**: `keep-awake/` 主分支（D 环节完成后）
**初始评分**: 7 / 10

---

## P0 · 致命

（本角度未发现独立 P0；P0-1/P0-2 见 Agent 1，修复后同步解除语义风险。）

---

## P1 · 重要

### P1-1 · `info` 状态文件不是结构化 JSON

- **文件**: `keep-awake.ps1:167`
- **问题**: `info` 文件被写成 PowerShell 哈希字面量字符串 `"@{ mode = $mode; started = ... }"`，`status` 端再用正则 `Select-String 'started'` 读取。这既不机器可读，也与 `power-backup.json` / `strong-result.json` 的 JSON 风格不一致，未来扩展困难。
- **修复**: 使用 `ConvertTo-Json` 写入 JSON，并在 `Invoke-Status` 中用 `ConvertFrom-Json` 读取。

### P1-2 · `off` 恢复失败后丢失上下文

- **文件**: `keep-awake.ps1:207-216`
- **问题**: `Invoke-Off` 调用 `Invoke-StrongOp off` 失败后仍删除 `$ModeFile` / `$InfoFile`。用户运行 `status` 将看到「未保持唤醒」，但电源计划实际仍被修改，误导性强。
- **修复**: 与 Agent 1 P1-2 相同，恢复失败时保留 info 或写入 failure marker。

### P1-3 · 启动 watcher 后未等待 PID 文件即返回

- **文件**: `keep-awake.ps1:90`
- **问题**: `Start-Watcher` 通过 `Start-Process` 拉起守护进程后立即返回，不等待 `awake.pid`。紧跟其后的 `status` 或 fast 自动化脚本可能看到「未运行」的假阴性。
- **修复**: 循环等待最多约 2s 直到 `awake.pid` 出现且进程存活。

### P1-4 · 守护进程对 stop 哨兵的响应延迟最高 5s

- **文件**: `awake-watcher.ps1`
- **问题**: 主循环先 `Start-Sleep 5` 再检查 `$StopFile`，导致 `off` 的优雅停止最多等 5s。注释声称 ~5s 退出，但最优做法是先检查再睡。
- **修复**: 调整循环顺序：先检查 stop 哨兵，再睡眠/心跳。

### P1-5 · hooks 调用使用 `powershell.exe` 而非 `pwsh.exe`

- **文件**: `keep-awake.ps1`（`Get-HookCommand` / `Get-DisarmCommand`）
- **问题**: hook 命令硬编码 `powershell`，在仅安装 PowerShell 7 且未启用 Windows PowerShell 的环境会失败（虽然 Win11 默认有 Windows PowerShell 5.1）。
- **修复**: hook 命令里优先检测 `pwsh.exe`，回退 `powershell.exe`。

### P1-6 · `uninstall.ps1` 删除状态目录前未确认电源已还原

- **文件**: `uninstall.ps1:33`
- **问题**: 与 Agent 1 P0-1 同源。从语义角度，这意味着「卸载」不能保证系统回到安装前的睡眠行为。
- **修复**: 同 Agent 1 P0-1。

---

## P2 · 建议

- Hook 安装假设目标 `settings.json` 是标准 JSON；若用户使用了带注释的 JSONC 会解析失败。
- `normal` 模式下仍写 `strong-cmd` 为 `off`，语义上多余但无害。
- `statusline.ps1` 在 `Split-Path -Leaf $dir` 对根目录可能为空；可降级为完整路径。
- 建议为 `arm` / `disarm` 增加日志，便于 flex 模式调试。

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
