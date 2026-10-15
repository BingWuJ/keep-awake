# keep-awake 快速使用说明书

> 一句话：插电跑长任务时，请求阻止系统空闲睡眠；屏幕可以自己黑；正常运行不改合盖/电源计划，旧版恢复除外。

---

## 1. 使用（正常使用无需安装、无需管理员）

在 Windows 11 的仓库根目录执行；需安装 PowerShell 7，确保 `pwsh` 在 PATH 中。从其他目录调用时使用脚本的绝对路径。旧版残留清理是唯一可能需要提权的场景。

```powershell
# 开：插电时挡住系统空闲睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on

# 查看当前状态
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status

# 关：停止，恢复正常睡眠
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off
```

## 2. 行为细则（契约）

| 情况 | 行为 |
|---|---|
| 插电 + 已 `on` | 请求阻止系统空闲睡眠，不覆盖手动睡眠或系统/固件限制 |
| 拔电 | 下一次电源轮询释放（约 5 秒内），Windows 正常睡眠计时接管 |
| 插回电源 | 自动继续挡（不用重新 `on`） |
| 电池上 `on` | 不挡，如实提示（宁可不挡，不假装醒着） |
| 电源状态读不到 | 不挡，报错 |
| 屏幕 | 不阻止 Windows 显示超时关屏；具体超时取决于你的系统设置及其他程序 |
| 合盖 / 电源键 / 电源计划 | 正常运行不修改；旧版清理可能按备份恢复旧合盖与电源计划设置 |
| 重启 | 不保留，需要重新 `on` |

## 3. 重要提醒

- 用完务必 `off`。
- Agent（pi / Claude Code）按 `SKILL.md` 在长任务开始时 `on`、结束时 `off`。
- 正常使用不提权、不注册计划任务、不安装钩子；旧版清理可能请求 UAC、恢复旧电源设置并移除已有配置中的旧钩子。
- 这是一个共享开关，不按 Agent 计数；`off` 会对共用状态的任务一起放开。
- 不覆盖手动睡眠、合盖或电源键动作；Modern Standby 的实际行为依赖系统和固件。
- 检查 `$LASTEXITCODE`：`on` 失败不能当成已保护；`off` 清理失败也会返回非零。

## 4. 旧版升级

装过旧版的机器：运行 `off` 或 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`，会按备份恢复电源计划、删除旧任务，并移除已有 settings 文件中可识别的旧钩子。只有检测到旧任务、备份或 strong 残留文件时才可能请求一次 UAC；仅有旧钩子不提权。

取消 UAC、备份损坏或恢复失败时保留旧残留并返回非零。先处理错误再重试，勿为了消除提示手动删除电源备份。

## 5. 卸载

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

只有 `off` 成功且旧任务核验通过后才删 `%USERPROFILE%\.keep-awake\`。脚本缺失、任务仍在或目录被占用均返回非零，不报卸载成功。手动配置过的 Claude Code `statusLine` 需自行移除；详见 [README.md](README.md#状态行可选)，该配置不适用于 pi 原生 settings。

## 6. 出问题怎么办

| 现象 | 处理 |
|---|---|
| `on` 报「读不到电源状态」 | 检查电源/电池驱动；修好前工具不会挡睡眠（这是设计） |
| 状态显示 `⚠ stale` | 守护进程死了，重新 `on` |
| 旧版计划任务删不掉 | 保留备份，以管理员再运行一次卸载脚本 |
| `power-backup.json` 无法解析 | 不要删除备份；修复备份或手动核对恢复旧设置后再清理 |
| 卸载提示目录删不掉 | 关闭占用状态文件的程序、检查权限后重试 |
| `pwsh` 找不到 | 安装 PowerShell 7 并加入 PATH |

## 7. 自动回归与人工验收

隔离回归（不动真实状态、计划任务或 UAC）：

```powershell
pwsh -NoProfile -File .\tests\test-install-uninstall.ps1
```

人工验收必须由使用者本人执行。按 [验收清单](doc/accept/USER-ACCEPTANCE.md) 从零走通并记录结果；自动测试不能替你签字。
