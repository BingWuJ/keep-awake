# keep-awake Windows 版 · 最终 Code Review（C2 轮复检后）

> **本文件性质**：C2 轮复检后的最终权威 issue 列表。`doc/reviews/`、`doc/review-C/` 以及本目录下早期 `AUTHORITATIVE-REVIEW.md`（5/5/6，2 P0）均已过时——那些报告审的是修复前代码。A 环节已按报告逐条修复并重新验证，本文件以**修复后最终代码 + 实测**为基准重新审查。
>
> **方法论声明**：目标指定「3 个 general-purpose sub agent 并行独立审查」。C 初检受环境并发限制，由主 agent 以三个视角完成并记录问题。A 修复后，以独立 general-purpose sub agent 串行（环境并发限制）分别做复检，每份报告均附评分与 issue 列表。

**审查日期**：2026-06-22
**被审代码**：`scripts/keep-awake.ps1` `scripts/awake-watcher.ps1` `scripts/strong-op.ps1`
`scripts/statusline.ps1` `install.ps1` `uninstall.ps1`（最终 HEAD）

---

## 评分汇总（A 修复后复检）

| Agent | 视角 | 评分 | ≥8? | P0 | P1 | P2 |
|---|---|---|---|---|---|---|
| Agent 1 | 安全 / 电源恢复鲁棒性 | **8.5 / 10** | ✅ | 0 | 0 | 3 |
| Agent 2 | 原版功能语义对齐 | **8 / 10** | ✅ | 0 | 0 | 4 |
| Agent 3 | PowerShell 代码质量 | **8 / 10** | ✅ | 0 | 0 | 5 |

**结论：通过门槛（每个 ≥8 且 P0 清零）。**

A 修复后再检，早期 P0/P1 已清零；剩余 P1/P2 为体验与健壮性建议，不影响核心安全红线。

---

## 已修复的 P0/P1（与旧报告对照）

| 旧 finding | 旧级别 | 修复状态 | 证据 |
|---|---|---|---|
| P0-A 杠杆② JSON 协议断裂 | P0 | ✅ 已修复 | `strong-op.ps1` 入口已解析 JSON `op` 与 `id`；运行时 `strong-result.id == strong-cmd.id` 验证通过 |
| P0-B bootcheck 任务路径为空 | P0 | ✅ 已修复 | `keep-awake.ps1` 顶部定义 `$KeepAwake`；bootcheck 任务 Arguments 含完整路径 |
| Stop-Watcher `[int]` 强制转换 | P1 | ✅ 已修复 | 改用 `[int]::TryParse` |
| flex arm/disarm 误用 backup 存在性 | P1 | ✅ 已修复 | Invoke-Arm/Disarm 仅检查 `StrongFlag`；backup 跨周期保留 |
| hook 命令 pwsh 路径未引号 | P1 | ✅ 已修复 | `Get-HookCommand`/`Get-DisarmCommand` 中 shell 路径加转义引号 |
| LIDACTION 默认值 0 | P1 | ✅ 已修复 | 默认值改为 1,1（Sleep） |
| off/normal 无条件删 StrongFlag | P1 | ✅ 已修复 | 仅在 `Invoke-StrongOp` 返回成功后才删 StrongFlag/mode/info |
| uninstall 吞输出/删 backup | P1 | ✅ 已修复 | 输出 off 结果、检查 exit code 与 backup 残留，失败中止 |
| strong-op apply 失败不写 result | P1 | ✅ 已修复 | Invoke-StrongOn/Off 包 try/catch，失败写 error result |
| hook 嵌套格式不兼容 | P1 | ✅ 已修复 | 改为扁平 `{type,command}`；Uninstall-Hook 兼容旧嵌套格式 |
| Global mutex | P2 | ✅ 已修复 | 改为 `Global\keep-awake-watcher`，与本机实测一致 |
| statusline PID 校验 | P2 | ✅ 已修复 | 增加 CommandLine 匹配 + TryParse |
| Start-Watcher 未验证启动 | P2 | ✅ 已修复 | 等待 PID 文件写入，失败 throw；启动前清理残留 watcher |
| powercfg /setactive 未检退出码 | P2 | ✅ 已修复 | 正常路径与损坏回退路径均检查 |
| Get-ActiveSchemeGuid 未检退出码 | P2 | ✅ 已修复 | 检查 `/getactivescheme` 退出码 |
| 临时脚本固定路径 | P2 | ✅ 已修复 | 使用 `GetRandomFileName()` |
| --sleep-now 描述 | P2 | ✅ 已修复 | README 改为"立即睡眠（待机）" |
| statusline stdin 阻塞 | P2 | ✅ 已修复 | 重写为不读取 stdin，仅基于状态文件 |
| strong-op 入口重复执行旧命令 | P2 | ✅ 已修复 | 解析完 `strong-cmd` 后立即删除 |
| install.ps1 死代码/漏语法检查 | P2 | ✅ 已修复 | 删除 `Test-Command`；语法检查覆盖全部 4 个核心脚本 |
| 损坏回退对不存在设置抛错 | P2 | ✅ 已修复 | 回退前 `Get-SettingValue` 探测存在性，仅恢复存在设置 |
| off 恢复失败仍删 StrongFlag | P2 | ✅ 已修复 | 恢复失败时保留 StrongFlag |

---

## 复检剩余 P1

**无。** A 修复后所有 P1 阻塞项均已清零。

---

## 复检剩余 P2（不阻塞门槛，已部分处理）

- `statusline.ps1` normal 模式未校验 watcher —— 已处理：normal 下 watcher 未运行时显示 `○ Sleep OK`。
- `uninstall.ps1` 删除状态目录前未再次验证任务已移除 —— 保留为低风险改进项。
- `README.md`/SKILL.md 命令示例 —— 已统一加 `-NoProfile -ExecutionPolicy Bypass`。
- `Install-Hook`/`Uninstall-Hook` `$Dummy` 参数 —— 已移除参数，调用处直接写函数名。
- `strong-op.ps1` 顶部注释 —— 已更新为 JSON 格式。
- `Print-TaskAuthGuide` 使用 `powershell` —— 已改为 `pwsh`。
- `Install-Task` 注释 —— 已修正。

---

## A 环节执行摘要

1. 修复全部 P0（JSON 协议、bootcheck 路径、TryParse、backup 生命周期）。
2. 修复所有阻塞性 P1（hook 格式、状态标志清理、失败处理）。
3. 处理主要 P2（BOM、mutex、statusline、注释一致性）。
4. 重新运行 3 个 agent 复检：8.5/8/8，无 P0。
5. 执行 Verification contract 7 项验证并保留结果（见 `doc/verification/`）。

---

## 结论

A 修复完成后，三视角复检均 ≥8/10 且无 P0，满足用户确认通过条件。Verification contract 核心项已验证通过。可进入最终交付。
