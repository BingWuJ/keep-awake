# Agent 1 · 安全 / 电源恢复鲁棒性 Code Review（第 3 轮，基于最新代码）

> 审查时间：2026-06-22
> 审查基准代码：`scripts/keep-awake.ps1`(mtime 03:25)、`awake-watcher.ps1`、`strong-op.ps1`
> 审查方式：当前 sub-agent 环境未暴露 `Agent` 工具 schema，由审查者以「安全/恢复鲁棒性」单一视角独立通读代码产出，整合第 1/2 轮（`doc/reviews/*` 初版与 `doc/review-C/summary.md`）的全部 issue 并逐条核对当前代码状态。

**评分：8 / 10**

总体评价：相比第 1 轮（7/10），两条最关键的安全缺口已经闭合——`on normal` 切换时正确调用 `Invoke-StrongOp off` 恢复杠杆②（`keep-awake.ps1:185-188`），且新增了 `Invoke-BootCheck` + 登录计划任务（`keep-awake.ps1:397-414`、`Install-Task` 注册 `$BootTaskName` AtLogon），实现了目标要求的「`strong` 标志在但守护进程没跑 → 自动恢复电源」。备份/恢复/损坏兜底/Mutex 单实例/try-finally 清理框架完整且正确。剩余扣分集中在 powercfg 静默失败与 LIDACTION 兜底默认值两处 P1。

---

## 已修复（相比第 1 轮）✅

| 原 issue | 当前状态 | 证据 |
|---|---|---|
| P0 · `on normal` 未清理杠杆② | ✅ 已修 | `keep-awake.ps1:185-188`：`if ((Test-Path $StrongFlag) -or (Test-Path $BackupFile)) { $null = Invoke-StrongOp -Op 'off' }` |
| P0 · 缺少开机自检任务（第 2 轮指出） | ✅ 已修 | `Invoke-BootCheck`（L397-414）检测 `StrongFlag/BackupFile` 残留且 watcher 未运行时自动 `Invoke-StrongOp restore`；`Install-Task`（L416+）注册 `keep-awake-bootcheck` AtLogon 任务；`Uninstall-Task` 同步清理；entry switch 新增 `bootcheck` 分发 |
| Mutex 单实例 + try/finally 显式清标志 | ✅ 正确 | `awake-watcher.ps1`：`Global\keep-awake-watcher` Mutex `WaitOne(0)` 非阻塞 + `AbandonedMutexException` 恢复 + finally 显式 `SetThreadExecutionState(ES_CONTINUOUS)` + `ReleaseMutex`/`Dispose` |
| 备份保护「二次 on 不覆盖原备份」 | ✅ 正确 | `strong-op.ps1 Invoke-StrongOn`：`if (-not (Test-Path $BackupFile)) { 写备份 } else { 保留 }` |
| 损坏 backup 兜底 | ✅ 正确（除 LIDACTION 默认值，见下） | `Invoke-StrongOff` catch 块按 `$Defaults` 恢复 + 删 strong/backup + 写 `corrupt-fallback` |

---

## 未修复 Issue 列表

### P1 · 损坏兜底时 LIDACTION 默认值错误（应为 Sleep=1，不是 Do nothing=0）

- **文件:行号**：`scripts/strong-op.ps1:62-63`
- **当前代码**：`$Defaults = @{ LIDACTION = @{ AC = 0; DC = 0 }; ... }`
- **问题**：Windows「合盖动作」默认是 Sleep（索引 1），0 表示「Do nothing」。备份损坏兜底时把 LIDACTION 恢复为 0，会让支持该设置的设备合盖不睡——与「兜底到安全默认值」意图相反，违反安全红线「off/restore 必须恢复原值」的精神（兜底恢复应倾向于「更安全地睡」而非「更激进地不睡」）。
- **影响范围**：仅在「backup 文件损坏」且「设备存在 LIDACTION 设置」时触发；本机 LIDACTION 不存在，但发往其他设备的 release 会命中。
- **修复建议**：`LIDACTION = @{ AC = 1; DC = 1 }`（Sleep）。如对 DC（电池）合盖想更保守，DC 也可设 1。

### P1 · `Set-SettingValue` / `powercfg /setactive` 完全不检查退出码

- **文件:行号**：`scripts/strong-op.ps1:113-122`（`Set-SettingValue`）、`168`、`209`、`231`（三处 `[void](powercfg /setactive ...)`）
- **当前代码**：

  ```powershell
  [void](powercfg /setacvalueindex SCHEME_CURRENT $SubGuid $SetGuid $AcValue 2>&1)
  [void](powercfg /setdcvalueindex SCHEME_CURRENT $SubGuid $SetGuid $DcValue 2>&1)
  ```

- **问题**：`[void]` 丢弃输出且不检查 `$LASTEXITCODE`。若计划任务 elevation 失败、GUID 无效、值越界、或 `/setactive` 未提交，函数静默返回，`Invoke-StrongOn` 仍写 `StrongFlag` + `status:ok`，造成「已生效」假象，违反 never fake。
- **修复建议**：
  1. `Set-SettingValue` 内每次 `powercfg` 后检查 `$LASTEXITCODE`，非零时抛出或返回失败；
  2. `Invoke-StrongOn` 在 `/setactive` 后回读 `Get-SettingValue` 验证值确为 0，任一不符则 `Write-Result status:error` 且不写 `StrongFlag`；
  3. `Invoke-StrongOff` 同理，恢复失败时 `status:error` 引导用户走 `restore`。

### P2 · `off` 失败时保留 `StrongFlag`（语义可辩护，但提示不够清晰）

- **文件:行号**：`scripts/keep-awake.ps1:225-230`
- **当前代码**：`Invoke-Off` 在 `Invoke-StrongOp off` 返回 `$false` 时仅打印提示，不删 `StrongFlag`。
- **评估**：保留 `StrongFlag` 作为「电源尚未恢复」的标记其实**合理**——若强删会让 `status` 误报「合盖防护关」而电源实际还卡着。第 1 轮判 P1 偏重；现降为 P2。真正缺口是：`status` 输出未区分「strong 标志在但电源可能未恢复」与「正常 strong 生效」，用户无法从 status 看出需要手动 restore。
- **修复建议**：`Invoke-Status` 检测「`StrongFlag` 在但上次 `strong-result.json` 非 ok」时追加一行告警；或在 off 失败提示里明确「`strong` 标志保留以便追踪，电源未恢复」。

### P2 · `Invoke-StrongOp` 把 `corrupt-fallback` 当失败

- **文件:行号**：`scripts/keep-awake.ps1:151`（`return ($r.status -in @('no-backup'))`）
- **问题**：`strong-op.ps1` 的 corrupt-fallback 已按默认值恢复并删 backup，但 `Invoke-StrongOp` 只认 `ok`/`no-backup` 为成功，于是 `Invoke-Off` 会提示「杠杆②需提权恢复」——而实际已经兜底恢复了。
- **修复建议**：`return ($r.status -in @('ok','no-backup','corrupt-fallback'))`。

### P2 · `Get-SettingValue` 吞掉 powercfg 执行错误

- **文件:行号**：`scripts/strong-op.ps1:80-111`
- **问题**：`$ErrorActionPreference='Continue'` + 返回 `$null`，调用方无法区分「设置不存在」（正常）与「powercfg 执行失败」（权限/命令错误）。
- **修复建议**：检查 `$LASTEXITCODE`，失败时写 WARN 日志或抛出，让 `Invoke-StrongOn` 知道是探测缺失还是命令出错。

### P2 · 日志无轮转

- **文件:行号**：`scripts/awake-watcher.ps1:24`、`scripts/strong-op.ps1:35`
- **问题**：`Add-Content` 无限追加。watcher 非永久运行（off 即停），增长有限，但长期 flex 模式下仍可能累积。
- **修复建议**：启动时若日志 > 1MB 则截断或轮转。

---

## 加分项

- 三重保障完整：心跳循环（60s reassert）+ 命名 Mutex 单实例 + try/finally 显式清标志，完全对齐目标「关键技术约束」第 3 条。
- bootcheck 设计正确：检测 strong 残留 + watcher 未运行才恢复，避免误触发。
- `Test-WatcherRunning` 用 PID + `CommandLine -like '*awake-watcher.ps1*'` 双重校验，防 PID 复用误判。
- `Install-Task` 改用 `ScheduledTasks` 模块而非 `schtasks /tr` 命令行，规避引号地狱。

---

## A 环节复验点

1. 损坏 backup 兜底后，`powercfg /query` 的 LIDACTION（若存在）应为 1（Sleep）而非 0。
2. 模拟 powercfg 失败（如临时改名 powercfg.exe 或用无效 GUID），`strong-result.json` 应写 `status:error` 且 `StrongFlag` 不生成。
3. `off` 后 `strong-result.json` 为 `corrupt-fallback` 时，不再误报「需提权恢复」。
