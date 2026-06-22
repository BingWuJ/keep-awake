# keep-awake 快速使用说明书

> 一句话：跑长任务时让 Windows 11 不息屏、不睡眠，可选合盖也不睡。

---

## 1. 安装（只需一次）

```powershell
git clone https://github.com/aurthur/keep-awake.git
cd keep-awake
.\install.ps1
```

`install.ps1` 会弹一次 UAC，注册最高权限计划任务，以后 super/flex 模式不用再弹 UAC。

如果只想用普通模式（不息屏，合盖仍睡），**不需要安装**，直接跑下面的命令即可。

---

## 2. 常用命令

```powershell
# 最常用：让 AI / 长任务在干活时保持唤醒，Agent 停下自动放开
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on flex

# 一直不睡（合盖、拔外屏、电池都不睡），直到你手动 off
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on super

# 只开盖时不息屏/不空闲睡，合盖就睡
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on normal

# 查看当前状态
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status

# 停止，恢复正常睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off

# 停止并立即睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off --sleep-now

# 应急：如果电源计划看起来没恢复，手动恢复
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 restore
```

---

## 3. 模式怎么选

| 场景 | 推荐模式 | 说明 |
|---|---|---|
| AI Agent 自动跑批 / 你一会儿发消息、一会儿走开 | **flex** | 干活时全防护，停下自动省电 |
| 渲染、下载、编译，离开几小时 | **super** | 一直不睡，记得回来 `off` |
| 只是人坐电脑前，不想息屏 | **normal** | 合盖就睡，最安全 |

---

## 4. 重要提醒

- **super 模式**：合盖无外屏时会发热，电池也不睡，用完务必 `off`。
- **flex 模式**：依赖 pi/Claude Code hooks；如果你不用这些 Agent，手动 `arm`/`disarm` 也有效。
- **所有模式**：只要运行 `off` 就会恢复默认睡眠行为。
- **合盖防护**：第一次使用 super/flex 前，必须先运行 `install.ps1` 或 `install-task` 授权。

---

## 5. 卸载

```powershell
.\uninstall.ps1
```

会停止防护、删除计划任务、移除 hooks、清理状态目录。

---

## 6. 出问题怎么办

| 现象 | 处理 |
|---|---|
| super/flex 提示"合盖防护还需一步" | 运行 `.\install.ps1` 或 `keep-awake.ps1 install-task` |
| off 后还是觉得电脑不睡 | 运行 `keep-awake.ps1 restore` |
| 状态不对 | 运行 `keep-awake.ps1 status` 看当前模式 |

详细说明见 `README.md`，实现细节见 `doc/reviews-C2/`。
