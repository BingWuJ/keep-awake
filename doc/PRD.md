# PRD — keep-awake 契约重定（Windows 防睡眠工具）

> 来源：2026-10-14 grilling 会话，所有决策已由用户逐条确认（是/否作答记录见 `doc/工作进度.md`）。
> 本文档是契约的忠实整理，不含新增需求。

## 1. 目标

插电跑长任务（AI Agent、下载、渲染）时，挡住 Windows 系统空闲睡眠；任务完成或拔电后恢复 Windows 正常睡眠行为。纯 PowerShell，无管理员要求。

## 2. 硬约束（用户明确否决项，任何实现不得违反）

- ❌ 正常防睡眠不修改电源计划（`powercfg` 零调用）；旧版恢复是唯一例外，见 §3.5。
- ❌ 不注册计划任务，不弹 UAC（旧版残留清理是唯一例外，见 §3.5）。
- ❌ 不强制屏幕常亮：守护进程不得设置 `ES_DISPLAY_REQUIRED`。
- ❌ 不修改合盖动作、电源按钮行为。
- ❌ 不安装钩子、不创建 pi / Claude Code 的 `settings.json`；仅移除已有文件中的旧钩子，见 §3.6。
- ❌ 不跨重启保留状态（无登录自启）。
- ❌ 电池上不挡睡眠（用户否决「电池也醒着」），且不得假装在挡。
- ❌ 失败必须诚实：读不到电源状态 → 不挡并报错；清理失败 → 如实报告，不静默吞掉。

## 3. 功能需求

### 3.1 `on` 命令
插电时启动守护进程挡系统空闲睡眠，exit 0；电池上仍启动但明确提示「未挡睡眠」；电源状态读不到时 exit 1 且不启动。重复 `on` 幂等。提示用完 `off`。

### 3.2 守护进程 `awake-watcher.ps1`
- 持 `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`，**不设** `ES_DISPLAY_REQUIRED`。
- 每 60 秒重新申明（防睡眠恢复后标志丢失）；每 5 秒轮询电源状态。
- 插电 → 持有；拔电 → 立即释放并标记 `released-battery`；插回 → 自动续挡；读不到 → 释放并标记 `error-power-unknown`；API 返回失败 → 释放并标记错误。
- 单实例（Global mutex + pid 文件）；`~/.keep-awake/stop` 哨兵出现后 ~5s 内退出；退出时 try/finally 显式清标志并删 pid 文件。
- 状态发布到 `~/.keep-awake/watcher-state`；日志超 256KB 轮转。

### 3.3 `off` 命令
停守护进程、删 `mode`/`info`/`watcher-state`；电源计划从未被新版本修改所以无需恢复；不创建任何 settings 文件；无旧残留时全程无 UAC。

### 3.4 `status` 命令
如实显示：未开启 / 挡住中（插电）/ 已开启但电池未挡 / 电源读取失败；显示电源来源；说明屏幕策略与「合盖/电源键/电源计划从不修改」；检测到旧版残留时警告。

### 3.5 旧版残留清理
`off` / `uninstall.ps1` 检测旧版遗留：`keep-awake-strong`、`keep-awake-bootcheck` 计划任务，`power-backup.json`、`strong`、`strong-cmd`、`strong-result.json` 文件。有残留时生成自包含提权脚本（不依赖已删除的旧 strong-op.ps1）：按备份恢复电源计划 + 注销任务；成功后删残留文件并复核清零；失败（含 UAC 取消）保留残留并如实报告。

### 3.6 旧钩子移除
仅当 `~/.pi/agent/settings.json` / `~/.claude/settings.json` **已存在**时检查（绝不创建目录或文件）；只删除 command 含 `keep-awake.ps1` + `arm`/`disarm` 标记的条目；其余钩子原样保留。

### 3.7 `statusline.ps1`
可选 statusLine provider。只读状态文件输出单行：`● Awake (AC)` / `◐ Awake idle (battery - not held)` / `⚠`（error 或 stale）/ `○ Sleep OK`。不读 stdin。

### 3.8 `install.ps1` / `uninstall.ps1`
install：核心脚本语法检查 + 旧残留检测 + 用法提示，不注册任何东西。uninstall：跑 `off` → 核验旧任务已删 → 删 `~/.keep-awake/` 整个状态目录；旧任务删不掉时 exit 1 并提示管理员重跑。

### 3.9 文档一致性
`SKILL.md`、`README.md`、`README.en.md`、`QUICKSTART.md` 的命令与行为描述必须与代码一致；不得出现合盖不休眠、强制亮屏、super/flex 等旧契约宣传。

## 4. 非功能需求

- 全机单开关：无引用计数，最后一次命令生效，`off` 一定放开。
- 幂等：重复 `on` / `off` 安全。
- 非 Windows 不支持（可失败但报错清晰）。
- 所有 .ps1 为 UTF-8 BOM。

## 5. 验收标准

- 用户本人按手册从零走通：`on` → `status` → `off`，并签字。
- 守护进程运行时电源计划字节级不变、无新计划任务、settings.json 未被触碰（已实测哈希一致）。
