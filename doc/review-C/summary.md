> ⚠️ **SUPERSEDED（已过时）** — 本文件是第 2 轮 review，基于较早的代码状态（bootcheck、normal 清 strong、flex hooks 创建、statusline 换行等修复**之前**），结论已被第 3 轮权威 review 取代。
> 请改看 **`doc/reviews/SUMMARY.md`**（基于最新代码，逐条核对了本文件的 issue 真实状态）。

# C·3 代码审查汇总（第 2 轮 · 已过时）

> 说明：当前环境没有可用的 `Agent` / subagent 工具，因此由主 agent 直接执行 3 个角度的独立审查，并按相同格式输出评分与 issue。

## 审查范围

- `scripts/keep-awake.ps1`
- `scripts/awake-watcher.ps1`
- `scripts/strong-op.ps1`
- `scripts/statusline.ps1`
- `install.ps1`
- `uninstall.ps1`
- `README.md` / `SKILL.md`

## Agent 1：安全 / 故障恢复 / 电源计划防卡

评分：**8 / 10**（修复后目标 9 / 10）

| 级别 | 文件 | 位置 | 问题 | 影响 |
|------|------|------|------|------|
| P0 | `keep-awake.ps1` | `Install-Task` / `Uninstall-Task` | **缺少开机自检任务**。目标要求“若 `strong` 标志在但守护进程没跑 → 自动恢复电源”，当前只有 `restore` 子命令，没有随登录自动执行的 bootcheck 任务。 | 系统重启后如果状态文件残留，电源计划可能永远卡在不睡状态。 |
| P1 | `keep-awake.ps1` | L169-171（`normal` 分支） | `on normal` 只把 `strong-cmd` 写成 `off`，**没有真正调用杠杆②恢复**。若用户从 super/flex 直接切到 normal，合盖防护可能仍然生效。 | normal 语义被违背。 |
| P2 | `strong-op.ps1` | `Set-SettingValue` | `powercfg /setacvalueindex` 等调用没有检查 `$LASTEXITCODE`，失败也静默。 | 错误可能被忽略。 |
| P2 | `strong-op.ps1` | `Invoke-StrongOff` | 还原时使用备份文件里的 scheme GUID，若用户在此期间切换了电源方案则会把活动方案切回旧方案。 | 低概率状态漂移。 |

## Agent 2：与 macOS 原版语义 / 功能对齐

评分：**8 / 10**（修复后目标 9 / 10）

| 级别 | 文件 | 位置 | 问题 | 影响 |
|------|------|------|------|------|
| P1 | `keep-awake.ps1` | L271-279（`Get-HookTargets`） | `Get-HookTargets` 只返回**已存在**的 `settings.json`。若用户首次安装 pi/Claude Code 且没有 `settings.json`，`on flex` 不会创建 hooks，自动循环失效。 | flex 模式核心场景 broken。 |
| P1 | `keep-awake.ps1` | L169-171 | 同 Agent 1：`on normal` 不清除 strong 状态。 | 模式切换语义错误。 |
| P2 | `statusline.ps1` | L60、L62 | `[Console]::Out.Write($out)` 输出**没有换行符**。状态行 host 可能不识别或显示异常。 | 状态行显示异常。 |
| P2 | `keep-awake.ps1` | `Invoke-Off --sleep-now` | `rundll32 powrprof.dll,SetSuspendState 0,1,0` 在启用休眠时会进入休眠而非睡眠。 | `--sleep-now` 语义与“立即睡眠”有偏差。 |

## Agent 3：PowerShell 代码质量 / 可移植性

评分：**7 / 10**（修复后目标 9 / 10）

| 级别 | 文件 | 位置 | 问题 | 影响 |
|------|------|------|------|------|
| P0 | 所有 `*.ps1` | 文件级 | 脚本**没有 UTF-8 BOM**。在 Windows PowerShell 5.1 下会被按系统默认 ANSI 解析，中文注释/字符串可能乱码或解析失败。目标明确写“编码 UTF-8 BOM”。 | Windows PowerShell 5.1 下行为不可预期。 |
| P1 | `keep-awake.ps1` | L91、L397、L425 | `Start-Process -ArgumentList ..., "`"$Watcher`""` 手动加了引号，`Start-Process` 会自动为含空格参数加引号，重复引号会导致路径解析失败。 | 路径含空格时启动失败。 |
| P1 | `statusline.ps1` | L60、L62 | 同 Agent 2：缺少换行。 | 状态行异常。 |
| P2 | `keep-awake.ps1` | L281-289（`Get-HookCommand`/`Get-DisarmCommand`） | Hook 命令写死 `powershell`，优先使用 `pwsh` 更好。 | 在仅安装 PS7 的环境中可能走旧版。 |
| P2 | `keep-awake.ps1` | L271-279 | 同 Agent 2：不创建缺失的 `settings.json`。 | 首次使用 flex 失败。 |

## 结论

- 当前 3 个角度评分：8 / 8 / 7。
- 需要进入 A 环节修复：**P0 开机自检**、**P0 UTF-8 BOM**、**P1 on normal 不清 strong**、**P1 flex hooks 不创建 settings.json**、**P1 Start-Process 引号问题**、**P1/P2 statusline 不换行**。
- 修复后预期评分：9 / 9 / 9。
