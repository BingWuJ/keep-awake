# Agent 1 · 安全 / 电源恢复鲁棒性审查报告

**审查日期**: 2026-06-22
**被审代码**: `keep-awake/` 主分支（D 环节完成后）
**初始评分**: 6 / 10

---

## P0 · 致命

### P0-1 · uninstall.ps1 删除状态目录时可能销毁未恢复的电源备份

- **文件**: `uninstall.ps1:33`
- **问题**: 脚本先调用 `off` / `uninstall-hook` / `uninstall-task`，然后无条件 `Remove-Item -Path $StateDir -Recurse -Force`。如果 `keep-awake-strong` 任务未注册（或 `off` 因权限失败），`power-backup.json` 可能仍存在且电源计划尚未还原。此时删除状态目录会把备份一起抹掉，导致系统被永久卡在不睡状态，违反安全红线「`off` 永远复位一切」和「安装/卸载无残留」。
- **修复**: 删除 `$StateDir` 前检查 `strong` 标志或 `power-backup.json`；若存在则保留目录并提示用户先 `restore`。

### P0-2 · 计划任务并发/旧实例竞争导致 strong-op 结果不可信

- **文件**: `keep-awake.ps1:120` 与 `keep-awake.ps1:388`
- **问题**: `Invoke-StrongOp` 用 `Stop-ScheduledTask` 结束旧实例（对 HIGHEST 任务普通用户可能 UnauthorizedAccess），然后以 `MultipleInstances Parallel` 启动新实例。旧实例若未停或与新实例并发读写同一份 `strong-cmd` / `strong-result.json`，父进程可能读到旧结果或超时后误判，进而导致电源计划未改/未恢复却仍报告成功。
- **修复**: 在命令文件中加入请求 ID（或时间戳），`strong-result.json` 回写相同 ID；父进程只接受匹配 ID 的结果。或把任务设为 `IgnoreNew` 并避免强行 Stop-ScheduledTask。

---

## P1 · 重要

### P1-1 · 损坏备份兜底时向不存在的设置写入默认值

- **文件**: `strong-op.ps1:204`
- **问题**: 当 `power-backup.json` 损坏时，代码遍历 `$Settings` 中全部 4 项并调用 `Set-SettingValue`，包括本机可能不存在的 `LIDACTION`。虽然错误被吞掉，但可能把默认的 LidCloseAction=0 写到原本没有该设置的机器上。
- **修复**: 兜底前重新 `Get-SettingValue` 探测设置是否存在，仅对存在的设置写默认值。

### P1-2 · `Invoke-Off` 在杠杆②恢复失败后仍删除 mode/info

- **文件**: `keep-awake.ps1:216`
- **问题**: 即使 `Invoke-StrongOp off` 返回失败，`off` 仍删除 `$ModeFile` / `$InfoFile`，丢失恢复上下文，用户后续难以判断是否需要手动 `restore`。
- **修复**: 恢复失败时保留 `$InfoFile`（或写入 failure marker），直到 `restore` 成功再清理。

### P1-3 · Global Mutex 对普通用户可能创建失败

- **文件**: `awake-watcher.ps1:76`
- **问题**: `Global\` 命名空间需要 `SeCreateGlobalPrivilege`，标准用户常抛 `UnauthorizedAccessException`。当前代码会降级到无单实例保护，可能导致多个 watcher 同时持有 `ES_CONTINUOUS` 标志。
- **修复**: 创建 Global 失败时回退到 `Local\keep-awake-watcher`，仍能保证同一会话/用户内的单实例。

### P1-4 · `powercfg` 错误码未被校验

- **文件**: `strong-op.ps1`
- **问题**: `Set-SettingValue` 与 `/setactive` 后未检查 `$LASTEXITCODE`，失败时仍可能报告 `ok`。
- **修复**: 对关键 `powercfg` 调用捕获输出并检查返回码，失败时返回 `status='error'`。

---

## P2 · 建议

- `status` 输出使用 `Write-Host`，不利于脚本链式处理。
- `Invoke-StrongOp` 的 20s 超时在某些旧机器上可能偏紧。
- 缺少针对电源计划最终状态与原始备份的自动 diff 校验。

---

## 复评记录（A 环节后回填）

| 项目 | 状态 | 备注 |
|---|---|---|
| P0-1 | 待修复 | |
| P0-2 | 待修复 | |
| P1-1 | 待修复 | |
| P1-2 | 待修复 | |
| P1-3 | 待修复 | |
| P1-4 | 待修复 | |
