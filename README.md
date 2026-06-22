# keep-awake — 让 Windows 11 不休眠

[![平台: Windows 11](https://img.shields.io/badge/platform-Windows%2011-blue)](#系统要求与兼容性)
[![PowerShell](https://img.shields.io/badge/built%20with-PowerShell-5391FE)](#系统要求与兼容性)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**跑长任务时让 Windows 11 不息屏、不睡眠、不休眠** —— 保持屏幕常亮、防止系统休眠，还可以选择**合盖也不休眠**（笔记本）。一个开源的 **Windows 防休眠神器**，专为 **让 AI Agent / 自动化工具无人值守地持续运行** 而做。

---

## 为什么需要它

当你启动一个长任务 —— **AI Agent / Claude Code / Claude Code Connectors** 跑批、模型下载、视频渲染、项目构建、数据同步 —— 然后离开电脑，Windows 会息屏、睡眠，你的任务也跟着卡住。`keep-awake` 会在你需要的时间内一直摁住系统的睡眠开关，用完自动让开。

它就是为 **"我离开时让 AI 接着干活"** 这个场景做的，分三档强度，纯命令行操作。

## 功能特性

- 🔆 防止**息屏**、**空闲睡眠**、**磁盘睡眠**和空闲触发的**系统睡眠**；super/flex 还额外挡住合盖/电池睡眠。
- 🛡️ 可选的**「合盖也不休眠」** —— 合上盖子、拔掉外接屏、甚至用电池，都继续运行。
- 🎛️ **三种命名模式**（超级 / 灵活 / 普通）应对不同需求。
- ⚡ **灵活档自动循环**：**只在 Agent 干活时**唤醒，停下自动放开（靠 pi / Claude Code 钩子）。省电。
- 🧩 **可作为 Claude Code / pi Skill**（`SKILL.md`）—— AI Agent 能按意图驱动。
- 🪶 纯 PowerShell + 系统自带 API（`SetThreadExecutionState`、`powercfg`）。没有常驻后台服务，不装内核扩展。

## 三种模式

| 模式 | 作用 | 合盖时 | 需授权 |
|------|------|--------|--------|
| **普通 normal** | 开盖时不息屏 / 不空闲睡 | 合盖即睡 | 否 |
| **灵活 flex** ⭐ | **只在 Agent 干活时**唤醒，停下自动放开 | 干活时不睡 | 是（计划任务免密） |
| **超级 super** | 一直不睡，直到你停 —— 合盖 / 拔外屏 / 电池都不睡 | 不睡 | 是（计划任务免密） |

⭐ 日常推荐 **灵活档**：干活时全防护，闲下来自动省电。

## 系统要求与兼容性

- **仅支持 Windows 11**（依赖 `SetThreadExecutionState` 和 `powercfg`）。Windows 10 未测试，可能工作但不保证。
- **PowerShell 7 (pwsh.exe)** 推荐；Windows PowerShell 5.1 也能跑核心脚本，但计划任务内脚本需要 pwsh 环境。
- **核心命令行**（`scripts/keep-awake.ps1`）：无需额外依赖。
- **「合盖也不休眠」**：需要**一次性 UAC 授权**（见下文），因为它要切换系统电源设置（`powercfg`）。
- **灵活档自动循环**和**状态行**是**可选的 pi / Claude Code 集成**（用到 hooks / `statusLine`）。没有 pi/Claude Code 时，超级档和普通档照常可用，灵活档也能手动 arm/disarm。
- ⚠️ **带合盖的现代待机（S0 Modern Standby）笔记本**：本工具通过 `powercfg` 改 standby/hibernate timeout 来防止睡眠；部分 S0 设备的合盖行为由固件/驱动控制，`Lid close action` 设置可能不存在，脚本会诚实跳过该设置（never fake）。

## 安装

```powershell
git clone https://github.com/aurthur/keep-awake.git
cd keep-awake
.\install.ps1
```

`install.ps1` 会：

1. 检查核心脚本语法；
2. 注册一个**最高权限计划任务** `keep-awake-strong`（弹一次 UAC，此后免密）；
3. 安装 flex 模式钩子到 `~/.pi/agent/settings.json` 和 `~/.claude/settings.json`。

核心命令行无需安装、即装即用：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on flex
```

## 使用

### 命令行

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on normal      # 开盖不睡（合盖就睡）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on flex        # 干活时不睡，闲下来自动放开
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on super       # 一直不睡（合盖/拔电/电池）直到 off
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status         # 查看当前状态
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off            # 全部停止，恢复正常睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off --sleep-now # 停止并立即睡眠（待机/standby）
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 restore        # 手动恢复电源计划（应急）
```

### pi / Claude Code Skill

把仓库放到 `~/.claude/skills/keep-awake/`（或软链），或在 pi 的 skill 路径中引用，`SKILL.md` 会告诉 Agent 何时触发、用什么命令。

`on flex` 还会自动安装 pi / Claude Code 钩子：

- `UserPromptSubmit → arm`（你发消息时唤醒）
- `Stop → disarm`（Agent 停下时放开）

### 状态行（可选）

在 pi / Claude Code 的 `settings.json` 里添加：

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File E:\\\\keep-awake\\\\scripts\\\\statusline.ps1"
  }
}
```

它会在状态栏显示当前 keep-awake 状态（如 `● Awake (Super)` 或 `○ Sleep OK`）。

## 「合盖也不休眠」—— 一次性授权

合盖防护要切换系统电源设置（`powercfg`），需要管理员权限。为了不用每次弹 UAC，你只需**一次性**授权注册一个**最高权限计划任务**。`install.ps1` 已经帮你做了这一步。

如果你跳过了安装，可以之后单独运行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 install-task
```

这会弹一次 UAC，注册 `keep-awake-strong` 任务。此后 super/flex 的合盖防护免密生效。

**安全说明**：该任务只执行 `scripts/strong-op.ps1`（备份/改/恢复电源计划），不做其他任何事。随时可撤销：`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 uninstall-task` 或运行 `uninstall.ps1`。

## 实现原理

两根系统「杠杆」：

1. **`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)`** —— 由 `awake-watcher.ps1` 守护进程持有，阻止息屏、空闲、磁盘、系统睡眠。无需权限。但**挡不住合盖睡眠**和**睡眠恢复后标志丢失**（PowerToys bug #32544），所以守护进程每 60 秒重新 assert，并配合单实例 Mutex + try/finally 显式清标志。
2. **`powercfg`** —— 改 `standby/hibernate timeout` 为 0（以及 `Lid close action` 为「不操作」，如果设备支持），挡住**一切**睡眠，含合盖 / 电池。通过 `keep-awake-strong` 计划任务以管理员身份执行，普通调用免密。

三种模式只是不同组合：`normal` = 杠杆①；`super` = 杠杆①+② 常开；`flex` = 杠杆①+② 仅在 Agent 干活时开（由 hooks 控制）。状态存在 `~/.keep-awake/`。

## 卸载

```powershell
.\uninstall.ps1
```

这会停止防护、删除计划任务、移除 hooks、清理状态目录。如果之前用 `install-task` 单独注册的任务也会被删除。

## 关键词

防休眠 · 防止系统休眠 · 防止电脑睡眠 · 让电脑不休眠 · 保持唤醒 · 保持清醒 · 显示屏常亮 · 屏幕常亮 ·
合盖不休眠 · 合盖不息屏 · 合盖也不睡 · 夹合模式 · 笔记本合盖继续运行 · 电池防休眠 · 挂机不休眠 ·
不息屏 · 防锁屏 · Windows 防休眠 · SetThreadExecutionState · powercfg ·
让 AI 持续运行 · AI Agent 防休眠 · Claude Code 防休眠 · Claude Code Connectors 不休眠 ·
自动化挂机不睡 · keep windows awake · prevent sleep · never sleep · keep awake with lid closed

## 许可证

[MIT](LICENSE)
