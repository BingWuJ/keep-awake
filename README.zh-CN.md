# keep-awake — 让你的 Mac 不休眠（合盖也能不休眠）

[![平台: macOS](https://img.shields.io/badge/platform-macOS-black)](#系统要求与兼容性)
[![bash + python](https://img.shields.io/badge/built%20with-bash%20%2B%20python-blue)](#系统要求与兼容性)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**跑长任务时让 Mac 不息屏、不睡眠、不休眠** —— 保持屏幕常亮、防止系统休眠，还可以选择**合上盖子也不休眠**
（夹合模式 / clamshell）、**拔了外接显示器也不睡**、**用电池也不睡**。一个小巧、可脚本化、开源的
**caffeinate / Amphetamine / Caffeine 防休眠神器替代品**，自带菜单栏控制面板 —— 专为
**让 AI Agent / 自动化工具无人值守地持续运行**而做。

> English docs → [README.md](README.md)

---

## 为什么需要它

当你启动一个长任务 —— **AI Agent / Claude Code / Claude Code Connectors** 跑批、模型下载、视频渲染、
项目构建、数据同步 —— 然后离开电脑，macOS 会息屏、休眠，你的任务也跟着卡住。`keep-awake` 会在你需要的
时间内一直摁住系统的睡眠开关，用完自动让开。

它就是为**"我离开时让 AI 接着干活"**这个场景做的，分三档强度，还带一个**菜单栏状态图标**，
让你随时一眼看到电脑是不是正被保持唤醒。

## 功能特性

- 🔆 防止**息屏**、**空闲睡眠**、**磁盘睡眠**和**系统睡眠**。
- 🛡️ 可选的**「合盖也不休眠」** —— 合上盖子、拔掉外接屏、甚至用电池，都继续运行。
- 🎛️ **三种命名模式**（超级 / 灵活 / 普通）应对不同需求。
- ⚡ **灵活档自动循环**：**只在 Agent 干活时**唤醒，停下自动放开（靠 Claude Code 钩子）。省电。
- 🍫 **菜单栏控制面板**：右上角随时看状态，点一下就能切模式 / 停止。
- 🧩 **可作为 Claude Code Skill**（`SKILL.md`）—— AI Agent 能按意图驱动（"干活时让我电脑别睡"）。
- 🪶 纯 `bash` + 系统自带工具（`caffeinate`、`pmset`）。没有需要照看的常驻进程，不装内核扩展。

## 三种模式

| 模式 | 作用 | 合盖时 | 需授权 |
|------|------|--------|--------|
| **普通 normal** | 开盖时不息屏 / 不空闲睡 | 合盖即睡 | 否 |
| **灵活 flex** ⭐ | **只在 Agent 干活时**唤醒，停下自动放开 | 干活时不睡 | 是（合盖功能） |
| **超级 super** | 一直不睡，直到你停 —— 合盖 / 拔外屏 / 电池都不睡 | 不睡 | 是（合盖功能） |

⭐ 日常推荐 **灵活档**：干活时全防护，闲下来自动省电。

## 系统要求与兼容性

- **仅支持 macOS。** 本工具依赖 `caffeinate` 和 `pmset`（macOS 特有），**不支持 Windows 和 Linux**。（在非 Darwin 系统上会直接报错退出。）
- **Apple Silicon 和 Intel** 芯片都支持。
- **核心命令行**（`scripts/keep-awake.sh`）：除了 macOS 本身，无需任何额外依赖。
- **菜单栏图标**：需要 **Python 3** + [`rumps`](https://pypi.org/project/rumps/)（安装脚本会自动装）。
- **「合盖也不休眠」**：需要**一次性 `sudo` 授权**（见下文），因为它要切换系统电源设置（`pmset disablesleep`）。
- **灵活档自动循环**和**状态行**是**可选的 Claude Code 集成**（用到 `~/.claude/settings.json` 的钩子 / `statusLine`）。没有 Claude Code 时，超级档和普通档照常可用，灵活档也能接到任意工具的钩子上。
- ⚠️ **带刘海的 MacBook**：当某个 App 菜单很宽时，菜单栏图标可能被藏到刘海后面。所以图标标题做得很短；你也可以 ⌘+拖动把它挪到更靠右的位置。

## 安装

```bash
git clone https://github.com/aurthur/keep-awake.git
cd keep-awake
./install.sh
```

安装脚本会装好菜单栏图标（右上角出现 `Sleep OK`），并注册开机自启。核心命令行无需安装、即装即用：

```bash
bash scripts/keep-awake.sh on flex
```

## 使用

### 命令行

```bash
bash scripts/keep-awake.sh on normal        # 开盖不睡（合盖就睡）
bash scripts/keep-awake.sh on flex          # 干活时不睡，闲下来自动放开
bash scripts/keep-awake.sh on super         # 一直不睡（合盖/拔电也不睡）直到 off
bash scripts/keep-awake.sh status           # 查看当前状态
bash scripts/keep-awake.sh off              # 全部停止，恢复正常睡眠
bash scripts/keep-awake.sh off --sleep-now  # 停止并立即休眠
```

### 菜单栏

`./install.sh` 之后，点右上角图标即可切模式或停止，当前模式会打勾。

### Claude Code Skill

把这个文件夹放到 `~/.claude/skills/keep-awake/`（或软链过去），AI Agent 就能按意图保持电脑唤醒。
`SKILL.md` 写了触发词和工作流。`on flex` 还会自动装 Claude Code 钩子
（`UserPromptSubmit → arm`、`Stop → disarm`），让防护跟着你的工作自动开关。

## 「合盖也不休眠」—— 一次性授权

合盖防护要切换系统设置（`pmset disablesleep`），需要 root。为了不用每次输密码，你只需**一次性**授权一条
**范围极窄的免密 `sudoers` 规则**。运行 `on super`（或 `on flex`）时它会打印出准确命令，或自己运行：

```bash
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" \
  | sudo tee /etc/sudoers.d/keep-awake >/dev/null \
  && sudo chmod 440 /etc/sudoers.d/keep-awake \
  && sudo visudo -cf /etc/sudoers.d/keep-awake && echo OK
```

**安全说明**：这条规则**只**放行免密切换 `pmset disablesleep`（开/关），别的什么都做不了。
随时可撤销：`sudo rm /etc/sudoers.d/keep-awake`。`off` 永远会把 `disablesleep` 复位为 `0`，绝不会卡在不睡的状态。

⚠️ 合盖且无外接屏时，持续高负载会发热；而且电池下也不睡 —— 用完记得 `off`。

## 实现原理

两根系统「杠杆」：

1. **`caffeinate -dims`** —— 挡住息屏、空闲、磁盘、系统睡眠。免权限。但**挡不住合盖睡眠**。
2. **`pmset disablesleep`** —— 挡住**一切**睡眠，含合盖 / 电池。需要 root（上面那次授权）。

三种模式只是不同组合：`normal` = 杠杆①；`super` = 杠杆①+② 常开；`flex` = 杠杆①+② 仅在 Agent 干活时开
（由 Claude Code 钩子控制）。状态存在 `~/.keep-awake/`，菜单栏程序每 3 秒读一次，由 `launchd` 保活。

## 卸载

```bash
./uninstall.sh
# 再撤销合盖授权：
sudo rm /etc/sudoers.d/keep-awake
```

## 关键词

防休眠 · 防止系统休眠 · 防止电脑睡眠 · 让电脑不休眠 · 保持唤醒 · 保持清醒 · 显示屏常亮 · 屏幕常亮 ·
合盖不休眠 · 合盖不息屏 · 合盖也不睡 · 夹合模式 · 笔记本合盖继续运行 · 电池防休眠 · 挂机不休眠 ·
不息屏 · 防锁屏 · `caffeinate` 图形界面 · `pmset disablesleep` · Amphetamine 替代 · Caffeine 替代 ·
防休眠神器 · 让 AI 持续运行 · AI Agent 防休眠 · Claude Code 防休眠 · Claude Code Connectors 不休眠 ·
自动化挂机不睡 · keep mac awake · prevent sleep · never sleep · keep awake with lid closed

## 许可证

[MIT](LICENSE)
