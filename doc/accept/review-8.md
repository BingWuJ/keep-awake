PASS

审查对象：`install.ps1`、`uninstall.ps1` 全文。依据 `doc/PRD.md` §3.8 与 `TASKS.md` 条目 8。审查时间：2026-10-16 00:04:00。只报告需求、实现及指定边界的阻断项。没有修改代码，没有删除真实 `%USERPROFILE%\.keep-awake`。

1. **uninstall.ps1:16–18、27–28、37 — off 失败或脚本缺失时仍删状态目录，并宣称守护进程已清理。** `off` 的退出码没有检查。找不到 `keep-awake.ps1` 时只打一句黄字，然后继续。任务核验通过后固定输出「守护进程、状态目录、旧版任务与备份均已清理」。**依据：PRD §3.8 要求先跑 off 再删状态目录；硬约束“失败必须诚实，不假装卸载干净”；审查指定的“off 失败时是否继续乱删”和“脚本缺失”。**
   - 隔离复现：TEMP 副本里的 `keep-awake.ps1` 只 `exit 1`，状态目录有 `mode` 和 `power-backup.json`，任务查询桩返回不存在。uninstall 退出码 0，状态目录被删，成功句仍在。
   - 不放置 `scripts\keep-awake.ps1`：先提示未找到脚本，再输出同一成功句，状态目录被删。

2. **uninstall.ps1:22–28、30–34 — 旧任务仍在时先删掉整个状态目录，再 exit 1。** 任务查询结果记下来之后，无论是否还有任务，都 `Remove-Item` 状态目录。exit 1 的提示是让管理员重跑，但备份文件已经没了。**依据：PRD §3.8“核验旧任务已删 → 删 ~/.keep-awake/”；§3.5 重跑时要能按备份恢复。审查指定的“残留任务核验时机”。**
   - 隔离复现：`off` 桩退出 0，`schtasks` 桩对两个旧任务名都返回存在，状态目录有 `power-backup.json` 和 `strong`。uninstall 退出码 1，提示管理员重跑；这两个文件和状态目录都已不在。

3. **uninstall.ps1:28、37 — 状态目录删不掉仍报卸载完成。** `Remove-Item -ErrorAction SilentlyContinue` 不检查目录是否还在。**依据：PRD §3.8 要删整个状态目录；硬约束不得假装卸载干净。审查指定的“状态目录被占用”。**
   - 隔离复现：`off` 桩退出 0，任务查询返回不存在，`mode` 以 `FileShare.None` 独占打开。uninstall 退出码 0，输出已卸载；状态目录和 `mode` 都还在。

对照核验（未单独构成阻断）：
- install 不注册任务、不提权：全文没有 `schtasks /create`、`Register-ScheduledTask`、`-Verb RunAs`。核心脚本缺失或语法错误时退出码 1，并在语法检查处停止。脚本齐全且把 `USERPROFILE` 指到空 TEMP 时，不创建 `.keep-awake`。
- 真实状态目录审查前后仍只有 `awake-watcher.log`（1776 字节，2026-10-15 06:37:34.341）。
- 未发现针对这两个脚本的测试文件，没有测试造假证据。

验证方式：复制原 `install.ps1` / `uninstall.ps1` 到 TEMP 仓库。`off` 用只 `exit 0/1` 的桩，任务查询用 PATH 上的 `schtasks.cmd` 桩，没有创建真实计划任务，没有弹 UAC。install 成功对照里的“检测到计划任务”来自始终返回 0 的桩，不是本机真实任务，不计入产品缺陷。

## 第 2 遍

PASS — 首轮三条都已消除：off 失败或脚本缺失时 exit 1 且保留状态；旧任务仍在时先 exit 1 并保留备份；目录删不掉时 exit 1，不报成功。

审查时间：2026-10-16 00:17:34。重新读取当前 `uninstall.ps1` 与 `tests/test-install-uninstall.ps1`。`uninstall.ps1` SHA-256 为 `50F121494771BF89A90EB64235A9FC13F2F49A785A147FD856918388111B0202`。没有修改产品代码或任务清单，没有写真实 `%USERPROFILE%\.keep-awake`（仍只有 `awake-watcher.log`，1776 字节，2026-10-15 06:37:34.341），没有弹 UAC，没有创建计划任务。

代码核对：`15–18` 缺脚本即 exit 1。`20–26` 检查 off 子进程 `$LASTEXITCODE`，非 0 或启动失败进入 catch 后 exit 1，删除在其后。`29–40` 任务仍在则 exit 1，提示管理员，且写明保留状态目录与备份。`43–51` `Remove-Item -ErrorAction Stop`，目录仍在则 throw，catch 后 exit 1，成功句只在这些检查之后。

独立运行 `tests/test-install-uninstall.ps1`：11 assertions; 0 failed。覆盖 off 失败、脚本缺失、任务残留并保留备份、目录占用、成功删除、重复卸载、install 不创建状态目录、核心脚本缺失、语法错误。任务桩是 PATH 上的 `schtasks.ps1`；本机 `PATHEXT` 不含 `.PS1`，但 pwsh 仍会优先执行该脚本，调用方 `$LASTEXITCODE` 随桩内容变为 1 或 0，因此“任务残留”断言不是空过。未发现断言与实现不符的假测试。

## 第 3 遍

PASS — 损坏备份不再被卸载当成 off 成功后删掉。`Invoke-Off` 先停守护进程，旧清理返回 false 时在成功句之前 exit 1；uninstall 因此不删状态目录。

审查时间：2026-10-16 00:26:45。只看这次差异：`scripts/keep-awake.ps1:394–411` 与 `tests/test-install-uninstall.ps1` 的 `real-off-corrupt-backup`。`keep-awake.ps1` SHA-256 为 `472BE763020A49FAAB08E60F00310EA40811549F87EFD6C81CE4A39EECC6ABA0`。没有修改产品代码，没有写真实 `%USERPROFILE%\.keep-awake`（仍只有 `awake-watcher.log`，1776 字节，2026-10-15 06:37:34.341），没有弹 UAC，没有创建计划任务。

代码顺序：`Stop-Watcher` 失败仍在调用 `Invoke-LegacyCleanup` 之前 exit 1，停止优先没有被这次修改倒过来。清理结果存入 `$legacyClean`；mode/info/watcher-state 清理之后，若为 false，输出「旧版清理失败。残留与备份已保留」并 exit 1，不输出 off 成功句。损坏 JSON 仍在生成提权脚本之前 return false，因此这条路径不提权。

独立运行 `tests/test-install-uninstall.ps1`：13 assertions; 0 failed。新增两条使用 TEMP 中的真实 `keep-awake.ps1` 和 `{broken` 备份，断言卸载 exit 1、原始备份仍在、没有卸载成功句。其余 11 条仍通过。断言检查的是真实脚本退出码和备份文件，不是只检查桩。
