# keep-awake

**跑长任务时，别让 Windows 11 睡着。**

插电挡住系统空闲睡眠，让 AI Agent 跑完；拔电立刻放手，屏幕照常变黑。纯 PowerShell 单脚本，不要管理员，不注册计划任务，不改电源计划。

[![平台: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#平台)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#平台)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## 一键安装

**给人类** —— PowerShell 7 窗口粘贴回车：

```powershell
irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex
```

装到 `%LOCALAPPDATA%\Programs\keep-awake`，自动跑语法自检和旧版残留检测，结束时打印要用的命令。不用管理员，不写注册表，不改 PATH。

**给 Agent** —— 把这段丢给它，或让它自己执行：

```powershell
$env:KEEP_AWAKE_AGENT=1; irm https://raw.githubusercontent.com/BingWuJ/keep-awake/main/setup.ps1 | iex
# 成功只输出一行：READY C:\Users\<你>\AppData\Local\Programs\keep-awake
```

Agent 模式无交互、无彩色输出、不弹提示，`READY` 加退出码 0 才算装好。装好后一律用绝对路径调用：

```powershell
& "$env:LOCALAPPDATA\Programs\keep-awake\scripts\keep-awake.ps1" on
```

> 下载即执行。要审就先存盘再跑：`irm <同上方 URL> -OutFile setup.ps1`，读完再 `.\setup.ps1`。
> 换目录用 `-Dir <路径>`，或者干脆 `git clone` 后 `.\install.ps1`。

## 三条命令

```powershell
$k = "$env:LOCALAPPDATA\Programs\keep-awake\scripts\keep-awake.ps1"
pwsh -NoProfile -File $k on      # 插电时挡住系统空闲睡眠
pwsh -NoProfile -File $k status  # 查电源、屏幕策略、守护进程
pwsh -NoProfile -File $k off     # 停止，恢复正常睡眠
```

## 做什么

- 🔌 **插电时挡住系统空闲睡眠**（`SetThreadExecutionState`），下载、渲染、跑批不被打断。
- 🪫 **拔电约 5 秒内放手**，Windows 正常睡眠计时接管；插回来自动继续挡。
- ❓ **读不到电源状态就不挡**，并如实报告——绝不假装在挡。
- 🖥️ **屏幕跟随 Windows 显示超时变黑**，不碰显示器空闲计时。

## 不做什么

- ❌ 不强制屏幕常亮。
- ❌ 不改合盖、电源键、电源计划；正常使用不调用 `powercfg`。
- ❌ 不要管理员、不注册计划任务、不弹 UAC、不安装钩子。
- ❌ 重启后不自动恢复，要重新 `on`。
- ❌ 不覆盖手动睡眠；Modern Standby 下不保证任务永不中断。

> 这些取舍来自对旧设计（super/flex 三档 + 高权限计划任务 + 合盖防护）的逐条盘问：合盖不休眠和强制亮屏用不上，却要付出持久管理员入口的代价，全部砍掉。

## 搭上 Agent

作为 pi / Claude Code 的 Skill：把安装目录放进 skill 路径（或软链），`SKILL.md` 会让 Agent 在长任务开始 `on`、结束 `off`。手动跑同样有效。

这是**共享开关**，不按 Agent 计数：`off` 会对共用该状态的任务一起放开。

## 实现原理

一根杠杆 + 电源监视，全部无提权：

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`** —— 由隐藏守护进程 `awake-watcher.ps1` 持有，只挡系统空闲睡眠。每 60 秒重新申明，每 5 秒查一次电源状态；按轮询结果释放、续挡或标记错误。
2. **状态透明** —— 守护进程把状态写进 `%USERPROFILE%\.keep-awake\`（`watcher-state`）；CLI 与状态行读取该状态并核实进程归属。`status` 还读取电源来源和检测旧任务，首次运行 CLI 会创建状态目录。

新版不设置 `ES_DISPLAY_REQUIRED`、不注册任务、不安装 hooks。旧版恢复/移除是唯一的电源计划和已有钩子清理例外。手动睡眠、合盖和电源键仍按 Windows 设置执行；Modern Standby 的实际功耗依赖系统与固件。

## 自检（可选）

```powershell
.\install.ps1
```

只做两件事：核心脚本语法检查、旧版残留检测。不注册任何任务。

## 状态行（可选）

以下是 **Claude Code** 的可选手动配置，不会由本工具写入。合并到 `~/.claude/settings.json`，不要覆盖已有配置；替换成实际安装路径，路径含空格时保留引号（参见 [官方状态行文档](https://code.claude.com/docs/en/statusline)）。pi 原生 settings 没有此 `statusLine` 字段，不要把此示例复制到 pi。

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"C:/Users/<你>/AppData/Local/Programs/keep-awake/scripts/statusline.ps1\""
  }
}
```

显示 `● Awake (AC)` / `◐ Awake idle (battery - not held)` / `⚠` 错误或残留状态 / `○ Sleep OK`。可单独运行：`pwsh -NoProfile -File .\scripts\statusline.ps1`。

## 从旧版升级

旧版（super/flex）通过高权限计划任务修改过电源计划。新版 `off` 或 `uninstall.ps1` 会一次性清理：

- 按备份恢复电源计划；
- 删除 `keep-awake-strong`、`keep-awake-bootcheck` 计划任务；检测到旧任务、备份或 strong 残留文件时才可能请求一次 UAC；
- 移除已有 pi / Claude Code settings.json 中可识别的旧版 keep-awake `arm`/`disarm` 钩子；仅有钩子不会触发 UAC。

备份损坏、恢复失败或取消 UAC 时，`off` / 卸载返回非零并保留旧残留。请先处理错误，勿直接删除备份。

## 卸载

```powershell
pwsh -NoProfile -File "$env:LOCALAPPDATA\Programs\keep-awake\uninstall.ps1"
```

停止守护进程、清理旧版残留、核验旧任务已删后，才删除 `%USERPROFILE%\.keep-awake\` 状态目录。缺少核心脚本、`off` 失败、旧任务仍在或目录删不掉时返回非零，不报卸载成功；先修复错误再重试。卸载不会删掉程序目录本身，也不需要——需要彻底移除时手动删除该文件夹。手动配置的 `statusLine` 不会被移除，要自己删或合并。

## 平台

- 仅支持 Windows 11（含 S0 现代待机设备）。
- 需要 PowerShell 7（`pwsh`）在 PATH 中；不承诺纯 Windows PowerShell 5.1 环境。
- 非 Windows 系统不支持。

## 关键词

防休眠 · 防止电脑睡眠 · 保持唤醒 · 挂机不休眠 · 防止 AI 任务被睡眠打断 ·
SetThreadExecutionState · keep windows awake · prevent sleep · keep awake ·
AI Agent 防休眠 · Claude Code 防休眠 · unattended · no admin · no scheduled task

## 许可证

[MIT](LICENSE)
