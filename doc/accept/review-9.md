PASS

审查对象：`SKILL.md`、`README.md`、`README.en.md`、`QUICKSTART.md`，对照当前 `scripts/keep-awake.ps1`、`awake-watcher.ps1`、`statusline.ps1`、`install.ps1`、`uninstall.ps1` 与 `doc/PRD.md` §3.9。审查时间：2026-10-16 00:39:57。静态核对，没有改文档或代码，没有创建临时测库。

1. **QUICKSTART.md:26 原句：「挡住系统空闲睡眠，长任务不被打断」。** 同一文件第 41 行写明不覆盖手动睡眠、合盖或电源键，且 Modern Standby 依赖系统与固件。代码只持有 `ES_SYSTEM_REQUIRED`，不保证长任务不被打断。契约表这句与实现和同页边界冲突。依据：PRD §3.9。

2. **仍把电源计划写成绝对不碰，与旧版恢复例外冲突。** 代码在有旧备份时会通过提权脚本调用 `powercfg` 恢复。这些原句没有这个例外：
   - `QUICKSTART.md:3`：「合盖/电源计划不动。」
   - `QUICKSTART.md:32`：「从不修改。」
   - `README.md:7`：「合盖、电源键、电源计划一律不碰。」
   - `README.en.md:7`：「never touches lid close, the power button, or the power plan.」
   - `SKILL.md` 描述区：「lid close, power button and the power plan are never touched.」
   同几份文档后面已写明旧版恢复例外，但这些入口句仍然是绝对说法。依据：PRD §3.9；§3.5 已确认的恢复例外。

已核对、不构成阻断：
- super/flex、合盖不休眠、强制亮屏只出现在“已删除”的历史说明里，没有当成现行为。
- 拔电约 5 秒、60 秒重申与 `awake-watcher.ps1` 的 `$PollSeconds = 5`、`$ReassertSeconds = 60` 一致。
- CLI 会创建状态目录，并读电源、CIM 进程归属和旧任务；`statusline.ps1` 不写文件、不读 stdin。
- `statusLine` 示例只给 Claude Code。官方文档 https://code.claude.com/docs/en/statusline 使用 `statusLine.type = command` 与 `command`。本机 pi `docs/settings.md` 无该字段。示例 JSON 可解析，路径指向现存的 `E:/keep-awake/scripts/statusline.ps1`，并要求含空格时保留引号。
- 手册要求 `pwsh`，并写明不承诺纯 5.1 完整流程。
- 卸载失败保留证据并返回非零，与当前 `uninstall.ps1` 一致。共享开关、Modern Standby 边界在提醒段已写明。
- `doc/accept/USER-ACCEPTANCE.md` 验收项未勾选，签字栏空白。
- PRD §3.8 现为「不注册任何东西」；§2 已指向 §3.5/§3.6 例外。未把这些历史说明当成新功能。

## 第 2 遍

PASS — 首轮两条入口句冲突已消除：不再写「长任务不被打断」，电源计划/合盖的入口句都限定为正常运行，并写明旧版恢复例外。

审查时间：2026-10-16 00:46:21。只重读这五处原文，没有改文档。

- `QUICKSTART.md:26` 现为「请求阻止系统空闲睡眠，不覆盖手动睡眠或系统/固件限制」。全文已无「长任务不被打断」。
- `QUICKSTART.md:3` 现为「正常运行不改合盖/电源计划，旧版恢复除外。」`QUICKSTART.md:32` 现为「正常运行不修改；旧版清理可能按备份恢复旧合盖与电源计划设置」。
- `README.md:7` 现为「正常运行不改合盖、电源键或电源计划（旧版恢复是唯一例外）。」`README.md:15` 的插电描述限定为空闲睡眠，并写明不保证覆盖手动睡眠或系统/固件限制。
- `README.en.md:7` 现为 “Normal operation leaves lid, power-button, and power-plan settings unchanged; legacy restoration is the only exception.” 插电描述同样限定不覆盖手动睡眠或 OS/firmware。
- `SKILL.md` 描述区现为 “Normal operation leaves lid, power-button and power-plan settings unchanged; legacy restoration is the exception.” 并含 OS/firmware 边界。
