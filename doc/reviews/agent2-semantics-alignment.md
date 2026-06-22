# Agent 2 · 原版功能语义对齐 Code Review（第 3 轮，基于最新代码）

> 审查时间：2026-06-22
> 审查基准代码：`scripts/keep-awake.ps1`(mtime 03:25)、`statusline.ps1`、`install.ps1`、`uninstall.ps1`、`README.md`、`SKILL.md`
> 审查方式：以「macOS 原版语义对齐」单一视角独立通读，整合前两轮 issue 并逐条核对当前代码。

**评分：8 / 10**

总体评价：相比第 1 轮（7/10），两条核心语义缺口已闭合——`on normal` 现正确清理 super/flex 残留的杠杆②（对齐 macOS 原版 normal=仅 caffeinate 的纯净语义）；flex hooks 现在会创建缺失的 `settings.json`（`Get-HookTargets` 总返回两个路径 + `Install-Hook` 用空 PSCustomObject 兜底），首次安装场景不再 broken；statusline 输出已加换行（`WriteLine`）。三模式组合逻辑、arm/disarm 随 Agent 工作循环、off 全复位、restore 应急命令均忠实对齐原版。剩余扣分主要是 flex arm 的一个边界 case（P1）与若干文档/提示一致性 P2。

---

## 已修复（相比第 1/2 轮）✅

| 原 issue | 当前状态 | 证据 |
|---|---|---|
| P0 · `on normal` 语义不纯（残留杠杆②） | ✅ 已修 | `keep-awake.ps1:185-188`：normal 分支调 `Invoke-StrongOp off` |
| P1 · flex hooks 不创建缺失的 `settings.json`（第 2 轮） | ✅ 已修 | `Get-HookTargets`（L283-294）总是 `New-Item -Force` 父目录并返回两路径；`Install-Hook`（L308）`$j = if (Test-Path $file) {...} else { [PSCustomObject]@{} }` |
| P2 · statusline 输出无换行（第 2 轮） | ✅ 已修 | `statusline.ps1`：`[Console]::Out.WriteLine($out)` 与 catch 分支 `WriteLine('○ Sleep OK')` |
| off 全清理（watcher + 电源 + hooks + mode/info） | ✅ 对齐 | `Invoke-Off`（L220-240）：Stop-Watcher → Invoke-StrongOp off → Uninstall-Hook → 删 ModeFile/InfoFile |
| status 显示模式/PID/任务状态 | ✅ 对齐（更完整） | `Invoke-Status` 输出友好模式名 + PID + 合盖防护开关 + 任务注册状态 |

---

## 未修复 Issue 列表

### P1 · flex arm 在「有 backup 无 strong 标志」时不再 re-arm

- **文件:行号**：`scripts/keep-awake.ps1:265-273`（`Invoke-Arm`）
- **当前代码**：

  ```powershell
  function Invoke-Arm {
      if ((Get-CurrentMode) -ne 'flex') { exit 0 }
      Start-Watcher
      if ((Test-Path $StrongFlag) -or (Test-Path $BackupFile)) {
          # Already armed by previous on flex; ensure strong-op still on.
          return
      }
      $null = Invoke-StrongOp -Op 'on'
      exit 0
  }
  ```

- **问题**：用户流程 `on flex`（生成 strong + backup）→ 手动 `restore`（删 strong、保留 backup）→ 下次 Agent 消息触发 arm：`Test-Path $StrongFlag`=false 但 `Test-Path $BackupFile`=true → `return`，不重新启用杠杆②。整个 flex 干活期间只有杠杆①在守护，合盖防护丢失，与 flex「干活时全防护」语义不符。
- **修复建议**：把条件简化为 `if (Test-Path $StrongFlag) { return }`。backup 存在只代表「有历史备份」，不代表「当前处于强防护」。arm 应仅在 strong 标志存在时跳过。

### P2 · `--sleep-now` 文案与 `SetSuspendState` 实际行为偏差

- **文件:行号**：`scripts/keep-awake.ps1:238`（`rundll32 powrprof.dll,SetSuspendState 0,1,0`）+ `236`（提示「立即休眠…」）
- **问题**：`SetSuspendState(Sleep=0, Hibernate=1, DisableWakeEvent=0)` 第二参数=1 表示「若启用休眠则休眠」。Windows 11 现代待机默认启用 hibernate，故实际进入休眠（写盘、恢复慢）而非睡眠（内存保持、恢复快）。文案「立即休眠」字面对了，但用户期望 `off --sleep-now` 通常是「轻睡眠」。
- **修复建议**（二选一）：
  - 文案改为「立即进入睡眠/休眠（取决于系统休眠设置）」并保留行为；
  - 或先 `powercfg /hibernate off` 临时关休眠 → `SetSuspendState 0,0,0` 强制睡眠 → 恢复 hibernate 状态（复杂，需备份）。
- **原版对照**：macOS `pmset sleepnow` 是明确的轻睡眠；Windows 无等价单命令，语义偏差可接受但需文档说明。

### P2 · `SKILL.md` 承诺「非 Windows 系统退出并提示」但代码未检测

- **文件:行号**：`SKILL.md` 末尾「The script exits with a clear message on non-Windows systems」 vs `scripts/keep-awake.ps1` 全文无 `$PSVersionTable.Platform` / `$IsWindows` 检测
- **问题**：文档承诺与实现不符。虽然这是纯 Windows 工具（非 Windows 上 PowerShell 本身可能不存在），但既然 SKILL.md 声明了就应兑现，否则改文档。
- **修复建议**（二选一）：
  - `keep-awake.ps1` 入口加 `if (-not $IsWindows) { Write-Error 'keep-awake is Windows-only.'; exit 1 }`（PS5.1 无 `$IsWindows`，需 `Get-CimInstance Win32_OperatingSystem` 兜底）；
  - 或删除 SKILL.md 该句。

### P2 · `status` 在 flex idle 期间信息不够直观

- **文件:行号**：`scripts/keep-awake.ps1:Invoke-Status`（约 L242-260）
- **问题**：flex disarm 后 watcher 已停但 `mode` 仍为 `flex`，status 输出「🌙 未保持唤醒（正常睡眠） 上次模式: Flex」，新用户无法区分「flex 空闲等待中」与「完全未启用」。
- **修复建议**：mode=flex 且 watcher 未运行时，输出类似「🌙 Flex 空闲中 · 等待下次 Agent 消息自动唤醒」。

### P2 · hook 幂等 marker 对路径中的 `arm`/`disarm` 敏感

- **文件:行号**：`scripts/keep-awake.ps1:Install-Hook` 幂等检查（约 L325-330）、`Uninstall-Hook`
- **问题**：`$h.command -like '*keep-awake.ps1*' -and $h.command -like "*$marker*"`，marker 为 `arm`/`disarm`。若仓库路径含 `arm`（如 `C:\arm-dev\keep-awake`），`-like '*arm*'` 总命中，误判已安装导致 hook 永不写入。
- **修复建议**：用更精确的 marker，例如命令须含 `keep-awake.ps1" arm`（带引号空格 + 子命令边界），或写入唯一注释 marker。

### P2 · `ConvertTo-Json` 重写 settings.json 产生 diff 噪音

- **文件:行号**：`scripts/keep-awake.ps1:Install-Hook` / `Uninstall-Hook`（`ConvertTo-Json -Depth 10 | Set-Content`）
- **问题**：重写后 key 顺序、缩进、空数组表示可能与用户原文件不同，造成 git diff 噪音或合并冲突。
- **修复建议**：安装/卸载前备份原文件（如 `.keep-awake-backup`），或在 README/SKILL 明示「会重写 settings.json 格式」。

### P2 · 连续 `on <同模式>` 无早期返回

- **文件:行号**：`scripts/keep-awake.ps1:Invoke-On`（L172-）
- **问题**：未检查当前是否已在同模式运行，连续两次 `on super` 会重写 mode/info、再启 watcher（Mutex 会拦）、再触发 strong-op 计划任务（有备份保护但多余）。
- **修复建议**：入口检查 `if ((Get-CurrentMode) -eq $Mode -and (Test-WatcherRunning)) { 提示已运行; return }`。

---

## 与 macOS 原版语义对照（更新版）

| 行为 | macOS 原版 | Windows 当前 | 差距 |
|---|---|---|---|
| normal | `caffeinate -dims`，合盖睡 | 杠杆①，合盖睡，且切换时清杠杆② | ✅ 对齐 |
| super | `caffeinate -dims` + `pmset disablesleep` | 杠杆①+②（未装任务时 never fake 告知） | ✅ 对齐 |
| flex | hooks + `caffeinate` | hooks + 杠杆①+②；arm 边界 case 残留 | ⚠️ P1 |
| off | 停 caffeinate、恢复 pmset | 停 watcher、调 strong-op off、清 hooks | ✅ 对齐 |
| status | 模式/PID | 模式/PID/任务状态/合盖防护 | ✅ 更完整 |
| restore | — | 应急手动恢复 | ✅ 新增 |
| bootcheck | — | 登录自检恢复 | ✅ 新增（超出原版） |
| --sleep-now | `pmset sleepnow`（轻睡眠） | `SetSuspendState 0,1,0`（可能休眠） | ⚠️ P2 |

---

## A 环节复验点

1. `on flex` → `restore` → 模拟 arm（或直接调 `keep-awake.ps1 arm` 前设 mode=flex 且删 strong 保留 backup）→ 确认 strong 标志重新生成、电源计划再次改 0。
2. `off --sleep-now` 文案与实际行为一致（或文档明确说明）。
3. SKILL.md「非 Windows 退出」承诺与代码一致。
