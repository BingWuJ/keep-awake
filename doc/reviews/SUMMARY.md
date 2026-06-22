# keep-awake Windows 版 Code Review 汇总（第 3 轮 · 权威）

> 本汇总由 C 环节（`check-review` 任务）产出。
> **审查方式诚实说明**：pi 目标 C 环节原要求「派出 3 个 sub agent 并行做 code review」。当前 sub-agent 运行环境未暴露 `Agent` / sub-agent 工具的调用 schema（与前两轮 review 遇到的限制一致：「当前环境没有可用的 Agent / subagent 工具」），无法派出真正的 sub-sub-agent。故由审查者以 **3 个独立、互补的单一视角** 分别通读当前最新代码产出等价结构化报告。每份报告独立评分、独立列 issue，审查者未在视角间做结论调和。
>
> **与第 1/2 轮的关键区别**：本轮基于**当前最新代码**（`keep-awake.ps1` mtime 2026-06-22 03:25，含 bootcheck、normal 清 strong、flex hooks 创建、statusline 换行等 D 阶段修复），逐条核对前两轮 issue 的「已修/未修」真实状态，消除前两轮（`doc/reviews/*` 初版 7/7/8 与 `doc/review-C/summary.md` 8/8/7）的冲突。

## 评分汇总

| Agent | 视角 | 评分 | 是否 ≥ 8 | P0 | P1 | P2 |
|---|---|---|---|---|---|---|
| Agent 1 | 安全 / 电源恢复鲁棒性 | **8 / 10** | ✅ | 0 | 2 | 4 |
| Agent 2 | 原版功能语义对齐 | **8 / 10** | ✅ | 0 | 1 | 6 |
| Agent 3 | PowerShell 代码质量 | **7 / 10** | ❌ | 1 | 2 | 9 |

**当前状态：未通过门槛。**
门槛 = 每个 agent 评分 ≥ 8 **且** 无任何 P0 issue。当前 Agent 3 评分 7 且有 1 条 P0（UTF-8 BOM 缺失，违反目标硬约束）。

---

## P0 Issue（必须 A 环节清零）

### P0-1 · 所有 `.ps1` 文件缺少 UTF-8 BOM【Agent 3】

- **位置**：`scripts/keep-awake.ps1`、`scripts/awake-watcher.ps1`、`scripts/strong-op.ps1`、`scripts/statusline.ps1`、`install.ps1`、`uninstall.ps1`（文件级）
- **实测**：6 文件首三字节均为 `23 21 2F`（`#!/`），无 `EF BB BF` BOM。
- **违反**：目标「关键技术约束」+ Agent 3 视角明确要求「编码 UTF-8 BOM」。
- **影响**：fallback 到 Windows PowerShell 5.1（中文系统按 GBK 解析）时，中文字符串乱码，奇数字节可能破坏引号配对引发语法错误。pwsh（PS7）用户不受影响。
- **修复**：6 文件统一加 UTF-8 BOM（见 Agent 3 报告的 PowerShell 一行命令）。

---

## P1 Issue 速览（A 环节应修）

| # | issue | 视角 | 位置 | 一句话修复 |
|---|---|---|---|---|
| P1-1 | 损坏兜底 LIDACTION 默认值错误（0=Do nothing，应为 1=Sleep） | Agent 1 | `strong-op.ps1:62-63` | `$Defaults.LIDACTION = @{ AC = 1; DC = 1 }` |
| P1-2 | `Set-SettingValue` / `/setactive` 不检查 `$LASTEXITCODE`，失败静默写 `status:ok` | Agent 1 & 3 | `strong-op.ps1:113-122,168,209,231` | 封装 `Invoke-Powercfg` helper 查退出码，非零写 `status:error` 且不生成 `StrongFlag` |
| P1-3 | `Start-Watcher` 不验证子进程启动 | Agent 3 | `keep-awake.ps1:85-94` | 启动后轮询 `Test-WatcherRunning` 3s，失败读日志并诚实报错 |
| P1-4 | flex arm 在「有 backup 无 strong 标志」时不 re-arm | Agent 2 | `keep-awake.ps1:265-273` | 条件改为 `if (Test-Path $StrongFlag) { return }` |

---

## P2 Issue 速览（A 环节可选，不计门槛）

- `off` 失败保留 `StrongFlag`（语义可辩护，提示不清）【Agent 1】`keep-awake.ps1:225-230`
- `Invoke-StrongOp` 把 `corrupt-fallback` 当失败【Agent 1】`keep-awake.ps1:151`
- `Get-SettingValue` 吞 powercfg 执行错误【Agent 1】`strong-op.ps1:80-111`
- 日志无轮转【Agent 1 & 3】`awake-watcher.ps1:24`、`strong-op.ps1:35`
- `--sleep-now` 文案与 `SetSuspendState` 实际行为偏差【Agent 2】`keep-awake.ps1:236,238`
- SKILL.md 承诺「非 Windows 退出」但代码未检测【Agent 2】`SKILL.md` vs `keep-awake.ps1`
- `status` flex idle 信息不直观【Agent 2】`keep-awake.ps1:Invoke-Status`
- hook 幂等 marker 对路径中的 `arm`/`disarm` 敏感【Agent 2】`keep-awake.ps1:Install-Hook`
- `ConvertTo-Json` 重写 settings.json 产生 diff 噪音【Agent 2 & 3】
- 连续 `on <同模式>` 无早期返回【Agent 2】`keep-awake.ps1:Invoke-On`
- `Get-SettingValue` 二进制回退解析脆弱【Agent 3】`strong-op.ps1:103-110`
- `$mode`/`$Mode` 混用【Agent 3】`keep-awake.ps1:176`
- `InfoFile` 写 here-string 非结构化 JSON【Agent 3】`keep-awake.ps1:176`
- `Install-Task` 临时脚本路径嵌单引号【Agent 3】`keep-awake.ps1:420-421`
- 超时硬编码未参数化【Agent 3】
- `statusline.ps1` BOM 剥离仅 UTF-8【Agent 3】`statusline.ps1:15`
- 缺 PS 5.1 测试矩阵声明【Agent 3】

---

## 相比第 1/2 轮已修复的 issue ✅（本轮确认）

| issue | 原轮次 | 证据 |
|---|---|---|
| `on normal` 未清理杠杆②（曾 P0） | 第 1 轮 | `keep-awake.ps1:185-188` 已调 `Invoke-StrongOp off` |
| 缺少开机自检任务（曾 P0） | 第 2 轮 | `Invoke-BootCheck`(L397-414) + `Install-Task` 注册 `$BootTaskName` AtLogon + entry `bootcheck` 分发 |
| flex hooks 不创建缺失 `settings.json`（曾 P1） | 第 2 轮 | `Get-HookTargets`(L283-294) 总返回两路径 + `Install-Hook`(L308) 空对象兜底 |
| statusline 输出无换行（曾 P1/P2） | 第 2 轮 | `statusline.ps1` 用 `[Console]::Out.WriteLine` |
| hook 命令写死 powershell（曾 P2） | 第 2 轮 | `Get-HookShell` 优先 pwsh fallback powershell |
| `Install-Task` 用 schtasks 命令行（曾 P1/P2） | 第 1/2 轮 | 改用 `ScheduledTasks` 模块 |
| macOS 文件清理（`.sh`/`.py`/`README.en.md`） | D8 | git status 显示 D，README/SKILL 已 Windows-only |

---

## 完整报告文件

- `agent1-security-recovery.md` — 安全 / 电源恢复鲁棒性（8/10）
- `agent2-semantics-alignment.md` — 原版功能语义对齐（8/10）
- `agent3-powershell-quality.md` — PowerShell 代码质量（7/10）

> 前两轮历史报告：`doc/review-C/summary.md`（第 2 轮，已被本轮取代/superseded）。

---

## A 环节建议（act-fix 任务的工作清单）

**必修（达门槛）**：

1. **P0-1**：6 个 `.ps1` 加 UTF-8 BOM。
2. **P1-1**：`$Defaults.LIDACTION` AC/DC 改 1。
3. **P1-2**：`Set-SettingValue` + `/setactive` 检查 `$LASTEXITCODE`，失败写 `status:error` 且不写 `StrongFlag`。
4. **P1-3**：`Start-Watcher` 启动后轮询验证。
5. **P1-4**：`Invoke-Arm` 条件改为仅 `Test-Path $StrongFlag`。

**建议修（提质）**：P2 中优先 `--sleep-now` 文案、SKILL.md 非Windows检测一致性、`corrupt-fallback` 当成功、连续 on 早期返回。

**复检要求**：修完 P0+P1 后，重跑受影响视角（Agent 3 必复检，Agent 1/2 视改动范围）的复验点，确认 3 视角均 ≥ 8 且 P0 清零，方进入最终端到端验证。
