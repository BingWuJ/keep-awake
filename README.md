# keep-awake — 让 Windows 11 在长任务时保持唤醒

[![平台: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#平台)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#平台)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**插电跑长任务时，挡住系统空闲睡眠；屏幕允许自己变黑；正常运行不改合盖、电源键或电源计划（旧版恢复是唯一例外）。**
一个纯 PowerShell 的 Windows 防睡眠小工具，专为让 AI Agent / 自动化任务无人值守地跑完而做。

---

## 它做什么 / 不做什么（诚实清单）

**做：**

- 🔌 **插电时**通过 `SetThreadExecutionState` 请求阻止系统空闲睡眠，减少下载、渲染、AI Agent 跑批因空闲睡眠中断；不保证覆盖手动睡眠或系统/固件限制。
- 🪫 **拔电后在下一次电源轮询时放开**（约 5 秒内），Windows 正常睡眠计时接管；插回电源自动继续挡。电池上绝不硬撑。
- ❓ 电源状态读不到时：**不挡，并如实报告**，绝不假装在挡。
- 🖥️ 不阻止屏幕按 Windows 自己的「关闭显示器」超时**自行变黑**；其他程序仍可能影响显示超时。

**不做：**

- ❌ 正常防睡眠不改电源计划、不调用 `powercfg`；仅清理旧版备份时例外恢复旧设置。
- ❌ 正常使用无需管理员、不注册计划任务、不弹 UAC；仅清理旧版任务/备份/strong 文件可能请求提权。
- ❌ 不强制屏幕常亮，不碰显示器空闲计时。
- ❌ 正常运行不改合盖动作、电源按钮行为；旧版恢复可能还原旧合盖设置。
- ❌ 不安装钩子、不创建 pi / Claude Code 的 `settings.json`；`off` 仅可能移除已有文件中的旧版 keep-awake 钩子。
- ❌ 重启后不自动恢复——需要重新 `on`。

> 这份取舍来自一次对旧设计（super/flex 三档 + 最高权限计划任务 + 合盖防护）的逐条盘问。
> 结论：合盖不休眠和强制亮屏用不上，却要付出持久管理员入口的代价，全部砍掉。

## 使用

无需安装，无需管理员：

```powershell
# 开：插电时挡住系统空闲睡眠（电池上不挡，会如实提示）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on

# 查：当前状态（含电源、屏幕、旧版残留检测）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status

# 关：停止，恢复正常睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off
```

作为 pi / Claude Code 的 Skill：把本仓库放进 skill 路径（或软链），`SKILL.md` 会让 Agent 在长任务开始时 `on`、结束时 `off`。没有 Agent 时手动跑同样有效。

## 实现原理

一根杠杆 + 电源监视，全部无提权：

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`** —— 由隐藏守护进程 `awake-watcher.ps1` 持有，只挡系统空闲睡眠。每 60 秒重新申明，每 5 秒查一次电源状态；按轮询结果释放、续挡或标记错误。
2. **状态透明** —— 守护进程把状态写进 `%USERPROFILE%\.keep-awake\`（`watcher-state`）；CLI 与状态行读取该状态并核实进程归属。`status` 还读取电源来源和检测旧任务，首次运行 CLI 会创建状态目录。状态行不写文件、不读 stdin。

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
