# keep-awake

**跑长任务时，别让 Windows 11 睡着。**

插电就挡住系统空闲睡眠，让 AI Agent 和自动化任务一路跑完；拔电立刻放手，屏幕该黑就黑。纯 PowerShell 单脚本，不要管理员，不注册计划任务，不改电源计划。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on
```

[![平台: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#平台)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#平台)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## 为什么需要它

Agent 跑到一半，机器按空闲计时睡下去，任务断在半路；醒来只剩半截结果和一个失联的终端。最常见的土办法是把屏幕超时改成「永不」，代价是显示器整夜亮着。

keep-awake 只做一件事：**插电时告诉 Windows「现在别因为空闲睡觉」**。屏幕该关就关，功耗和烧屏都不用你操心。

## 做什么

- 🔌 **插电时挡住系统空闲睡眠**（`SetThreadExecutionState`），下载、渲染、跑批不再被空闲睡眠打断。
- 🪫 **拔电就放手**：下一次电源轮询（约 5 秒内）释放，Windows 正常睡眠计时接管；插回来自动继续挡。
- ❓ **读不到电源状态就不挡**，并如实报告——绝不假装在挡。
- 🖥️ **屏幕跟随 Windows 自己的显示超时变黑**，不插手显示器空闲计时。

## 不做什么

- ❌ 不强制屏幕常亮。
- ❌ 不改合盖动作、电源键行为、电源计划；正常使用不调用 `powercfg`。
- ❌ 不要管理员、不注册计划任务、不弹 UAC、不安装钩子。
- ❌ 重启后不自动恢复——需要重新 `on`。
- ❌ 不覆盖手动睡眠；Modern Standby 下也不保证所有任务永不中断。

> 这套取舍来自一次对旧设计（super/flex 三档 + 最高权限计划任务 + 合盖防护）的逐条盘问。
> 结论：合盖不休眠和强制亮屏用不上，却要付出持久管理员入口的代价，全部砍掉。

## 三条命令

无需安装，无需管理员：

```powershell
# 开：插电时挡住系统空闲睡眠（电池上不挡，会如实提示）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on

# 查：当前状态（含电源、屏幕、旧版残留检测）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status

# 关：停止，恢复正常睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off
```

`status` 会核实守护进程归属并检测旧版残留；状态行不写文件、不读 stdin。

## 搭上 Agent

作为 pi / Claude Code 的 Skill：把本仓库放进 skill 路径（或软链），`SKILL.md` 会让 Agent 在长任务开始时 `on`、结束时 `off`。没有 Agent 时手动跑同样有效。

这是一个**共享开关**，不按 Agent 计数：`off` 会对所有共用该状态的任务一起放开。

## 实现原理

一根杠杆 + 电源监视，全部无提权：

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`** —— 由隐藏守护进程 `awake-watcher.ps1` 持有，只挡系统空闲睡眠。每 60 秒重新申明，每 5 秒查一次电源状态；按轮询结果释放、续挡或标记错误。
2. **状态透明** —— 守护进程把状态写进 `%USERPROFILE%\.keep-awake\`（`watcher-state`）；CLI 与状态行读取该状态并核实进程归属。`status` 还读取电源来源和检测旧任务，首次运行 CLI 会创建状态目录。

新版不设置 `ES_DISPLAY_REQUIRED`、不注册任务、不安装 hooks。旧版恢复/移除是唯一的电源计划和已有钩子清理例外。手动睡眠、合盖和电源键仍按 Windows 设置执行；Modern Standby 的实际功耗依赖系统与固件，不保证所有任务永不中断。

## 安装（可选）

```powershell
.\install.ps1
```

只做两件事：核心脚本语法检查、旧版残留检测。不注册任何任务。

## 状态行（可选）

以下是 **Claude Code** 的可选手动配置，不会由本工具写入。合并到 `~/.claude/settings.json`，不要覆盖已有配置；替换成实际仓库路径，路径含空格时保留引号（参见 [官方状态行文档](https://code.claude.com/docs/en/statusline)）。pi 原生 settings 没有此 `statusLine` 字段，不要把此示例复制到 pi。

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"E:/keep-awake/scripts/statusline.ps1\""
  }
}
```

显示 `● Awake (AC)` / `◐ Awake idle (battery - not held)` / `⚠` 错误或残留状态 / `○ Sleep OK`。可单独运行 `pwsh -NoProfile -File .\scripts\statusline.ps1` 查看。

## 从旧版升级

旧版（super/flex）通过最高权限计划任务修改过电源计划。新版 `off` 或 `uninstall.ps1` 会一次性清理：

- 按备份恢复电源计划；
- 删除 `keep-awake-strong`、`keep-awake-bootcheck` 计划任务；检测到旧任务、备份或 strong 残留文件时才可能请求一次 UAC；
- 移除已有 pi / Claude Code settings.json 中可识别的旧版 keep-awake `arm`/`disarm` 钩子；仅有钩子不会触发 UAC。

备份损坏、恢复失败或取消 UAC 时，`off` / 卸载返回非零并保留旧残留。请先处理错误，勿直接删除备份。

## 卸载

```powershell
.\uninstall.ps1
```

停止守护进程、清理旧版残留、核验旧任务已删后，才删除 `%USERPROFILE%\.keep-awake\` 状态目录。缺少核心脚本、`off` 失败、旧任务仍在或目录删不掉时返回非零，不报卸载成功；先修复错误再重试。用户手动配置的 `statusLine` 不会被卸载脚本移除，需要自行移除或合并。

## 平台

- 仅支持 Windows 11（含 S0 现代待机设备）。
- 本文命令和安装/卸载脚本要求 PowerShell 7（`pwsh`）在 PATH 中；不承诺纯 Windows PowerShell 5.1 环境的完整流程。
- 非 Windows 系统不支持。

## 关键词

防休眠 · 防止电脑睡眠 · 保持唤醒 · 挂机不休眠 · 防止 AI 任务被睡眠打断 ·
SetThreadExecutionState · keep windows awake · prevent sleep · keep awake ·
AI Agent 防休眠 · Claude Code 防休眠 · unattended · no admin · no scheduled task

## 许可证

[MIT](LICENSE)
