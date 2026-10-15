# keep-awake 用户亲自验收清单

> 自动回归与独立代码审查不等于用户签字。以下由使用者本人执行；不要勾选未实测项目。
> 要求 Windows 11 + PowerShell 7（`pwsh` 在 PATH 中）。从仓库根目录运行。不要在其他任务依赖本工具保持唤醒时执行 `off` 或卸载。

## 1. 从零走通

- [ ] 在普通非管理员终端运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`，语法检查通过；没有旧版残留时不弹 UAC、不注册任务。
- [ ] 插电，运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 on`，`$LASTEXITCODE` 为 0，报告插电挡系统空闲睡眠。
- [ ] 运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 status`，核对插电来源、守护进程 PID、运行状态和屏幕策略。
- [ ] 运行 `pwsh -NoProfile -File .\scripts\statusline.ps1`，只输出一行 `● Awake (AC)`。
- [ ] 再跑一次 `on`，未多开守护进程；核对系统进程中的 watcher 数量和 PID。
- [ ] 保持插电、无键鼠操作，等待超过系统显示超时：屏幕可黑；工具不保证覆盖其他程序的显示请求。确认长任务继续运行；必要时单独检查 Windows 电源请求。
- [ ] 若设备有电池：拔电，约 5 秒后 `status` 和状态行显示电池未挡；插回电源，约 5 秒后恢复挡住状态。
- [ ] 运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\keep-awake.ps1 off`，exit 0，守护进程退出；`status` 为未开启、状态行为 `○ Sleep OK`。
- [ ] 重复 `off` 安全；无旧残留时不弹 UAC，不新建 settings 文件。
- [ ] 另择空闲时重启或注销：不会自动启动 watcher。注意磁盘上可能保留上次 on 的文件，状态行可能显示 stale，这不是仍在防睡眠；再次 on 才恢复。

## 2. 安全边界

- [ ] 核对正常 on/off 前后电源计划、合盖和电源按钮设置未变；没有新增 keep-awake 计划任务。
- [ ] 如果有客户端 settings 文件，确认正常使用前后未变；只有可识别的旧版钩子清理是例外。
- [ ] 明白手动睡眠、合盖、电源键仍可能让机器睡眠；Modern Standby 实际效果取决于系统与固件。
- [ ] 明白开关不按 Agent 引用计数：一个任务的 off 会影响其他共用状态的任务。

## 3. 卸载（确认不再需要保护后）

- [ ] 运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`，成功时 exit 0，状态目录 `%USERPROFILE%\.keep-awake\` 被删除。
- [ ] 如果手动加过 Claude Code statusLine，自己移除或合并该配置。不要在 pi 原生 settings 中使用 Claude Code 的配置示例。
- [ ] 知道失败时不能视为卸载完成：缺核心脚本、off 失败、残留任务、目录占用都应处理后重试，不直接删备份。

## 4. 不在真实系统上强行制造的故障

- 运行 `pwsh -NoProfile -File .\tests\test-install-uninstall.ps1`，隔离复核失败保留证据、文件锁、重复卸载及安装异常。
- 旧版电源恢复/UAC 取消、读不到电源、API 失败等未实机验证时，记录为“未实测”；不为完成清单篡改真实电源备份或创建最高权限任务。
- 软件检查不能代替长时间待机/拔插电物理验证。任何一项不符合预期，停止并保留错误输出、退出码及日志。

## 签字（仅用户填写）

- 验收人：
- 时间：
- 通过项目 / 未实测项目：
- 失败与复现步骤：
- 是否接受交付：
