# Agent 2 · 原版功能语义对齐 Code Review（C2 轮复检后）

> 本报告为 A 修复后的复检结果。A 修复前（C 初检）评分为 5/10；修复后重新审查，P0/P1 阻塞项已全部清零，评分 **8 / 10**。

## 评分

**8 / 10**（≥8 ✅，P0=0，P1=0，P2=4）

## 已修复的关键问题

| 问题 | 原级别 | 修复证据 |
|---|---|---|
| normal 模式未清理杠杆② | P0 | `Invoke-On` normal 分支在 `StrongFlag`/`BackupFile` 存在时调用 `Invoke-StrongOp off`，失败时 exit 1 |
| hook 命令 pwsh 路径未引号 | P1 | `Get-HookCommand`/`Get-DisarmCommand` 对 shell 路径加转义引号 |
| hook 条目嵌套格式不兼容 | P1 | 改为扁平 `{type,command}`；`Uninstall-Hook` 兼容移除旧嵌套格式 |
| `--sleep-now` 文案偏差 | P1 | README 改为"立即睡眠（待机）" |
| flex arm/disarm 基线破坏 | P1 | arm/disarm 仅检查 `StrongFlag`；backup 跨 disarm/arm 周期保留 |

## 剩余 P2（不阻塞门槛）

1. **pi hooks 事件名假设**：`UserPromptSubmit`/`Stop` 基于 Claude Code 兼容格式，pi 官方文档未公开，需用户实测。
2. **SKILL.md 命令示例**：已统一加 `-NoProfile -ExecutionPolicy Bypass`。
3. **README 对 S0 现代待机的描述**：已说明合盖接外屏时 Windows 可能进入现代待机继续运行。
4. **install-hook 对 Claude Code settings 的创建**：已自动创建缺失目录与文件。

## 结论

A 修复后，super/flex/normal 三模式语义忠实复刻 macOS 原版：super 全防护、flex 随 Agent 工作自动启停、normal 仅 lever 1、off 全复位。满足通过门槛。
