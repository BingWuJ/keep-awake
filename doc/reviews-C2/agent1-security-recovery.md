# Agent 1 · 安全 / 电源恢复鲁棒性 Code Review（C2 轮复检后）

> 本报告为 A 修复后的复检结果。A 修复前（C 初检）评分为 5/10 并含 1 条 P0；修复后重新审查，P0/P1 阻塞项已全部清零，评分 **8.5 / 10**。

## 评分

**8.5 / 10**（≥8 ✅，P0=0，P1=0，P2=3）

## 已修复的关键问题

| 问题 | 原级别 | 修复证据 |
|---|---|---|
| 杠杆② JSON 协议断裂 | P0 | `strong-op.ps1` 入口解析 JSON `op`/`id`；`Write-Result` 回写 `id`；运行时 id 匹配验证通过 |
| bootcheck 任务路径为空 | P0 | `keep-awake.ps1` 顶部定义 `$KeepAwake = Join-Path $RepoScripts 'keep-awake.ps1'` |
| off 恢复失败仍删 StrongFlag | P1 | 恢复失败时保留 StrongFlag，仅删 mode/info |
| corrupt-backup 兜底崩溃 | P1 | 兜底前用 `Get-SettingValue` 探测存在性，仅恢复存在的设置 |
| powercfg /setactive 未检退出码 | P2 | 正常路径与损坏回退路径均检查 `$LASTEXITCODE` |
| Global mutex → Local（后又恢复 Global） | P2 | 最终代码使用 `Global\keep-awake-watcher`，与本机实测一致 |

## 剩余 P2（不阻塞门槛）

1. **日志无轮转**：长期运行可能无限增长（watcher 与 strong-op 均使用 `Add-Content`）。
2. **uninstall 删除状态目录前未二次确认任务已移除**：当前实现依赖任务移除与 off 的顺序，风险低。
3. **statusline 在 normal 模式下未显式校验 watcher 命令行**：已校验 PID 与 CommandLine，可再增强对 normal 模式的显式分支。

## 结论

A 修复后，安全红线全部守住：备份/恢复完整、never-fake 落实、bootcheck 自愈可用、异常恢复路径通过实测。满足通过门槛。
