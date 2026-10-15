BLOCKING

审查对象：`scripts/keep-awake.ps1` 的 `Invoke-Status`（364–387）及其调用的 `Test-WatcherRunning`（57–70）、`Get-LegacyArtifacts`（76–84）。依据 `doc/PRD.md` §3.4、§2 与 `TASKS.md` 条目 4。审查时间：2026-10-15 23:01:09。只报告需求、实现及指定边界的阻断项。没有修改代码，没有写 `%USERPROFILE%\.keep-awake`。

1. **scripts/keep-awake.ps1:369；调用链 scripts/keep-awake.ps1:367 → 59 — 零字节 watcher-state 或 pid 文件使 status 在显示任何状态前抛错。** `Get-Content -Raw` 对零字节文件返回 `$null`，随后无守卫地调用 `.Trim()`。`Invoke-On` 在 315–316 行已对同一读法加了 `$null` 判断；`Invoke-Status` 没有。pid 文件为空时，抛错发生在 `Test-WatcherRunning` 的第 59 行，该行不在函数自己的 try 里，`Invoke-Status` 也不捕获，因此到不了「未开启」。watcher 已确认运行但 `watcher-state` 为零字节时，抛错发生在第 369 行，到不了未知状态分支，电源行、屏幕策略和旧残留警告都不会输出。**依据：PRD §3.4 要求如实显示四态及未知运行态、电源来源和屏幕/合盖说明；审查指定的空文件边界，以及条目 1 已确认的「零字节文件上 `.Trim()` 抛错」；§2 失败必须诚实，崩溃并空白输出不是如实报告。**
   - 真实零字节文件：长度 0，`-Raw` 结果为 `$null`，`.Trim()` 抛出 `You cannot call a method on a null-valued expression.`
   - 隔离复现 A：TEMP 中 pid 指向命令行含 `awake-watcher.ps1` 的存活进程，`watcher-state` 为零字节。原 `Invoke-Status` 抛出同一错误，输出为空，没有「运行中」或「未挡」。
   - 隔离复现 B：pid 文件存在但为零字节，旁边预置 `mode=on` 与 `holding-ac`。原 `Invoke-Status` 同样抛错，输出为空，没有「未开启」。没有把 `holding-ac` 显示成挡住，但也没有完成规定的状态输出。

对照核验（这些路径未构成阻断）：
- 四态与未知态：未运行显示「未开启（正常睡眠行为）」；`holding-ac` 显示「挡住系统空闲睡眠（插电）」并带 PID 与 started；`released-battery` 显示「已开启但未挡睡眠（当前用电池）」；`error-power-unknown` 显示「电源状态读取失败，未挡睡眠」。`starting` 显示「守护进程运行中（状态: starting）」，没有写成挡住。
- 电源行：注入的 Online / Offline / Unknown 分别显示插电 / 电池 / 读不到。屏幕句为「不强制常亮，跟随 Windows 显示超时自动变黑。」合盖/电源键/电源计划句为「从不修改。」
- 不得假装在挡：`mode=on` 且状态文件为 `holding-ac`，但 pid 已死、pid 指向非 watcher、pid 文本不可解析、或 CIM 查询抛错时，均显示「未开启」，没有挡住句。CIM 失败由原 `Test-WatcherRunning` 的 catch 变成空命令行后返回 false。
- 仅含空白的状态文件不抛错，显示「运行中（状态: ）」，没有写成挡住。
- 旧残留：四个指定文件都能列出；只有 `power-backup.json` 时只报该文件；无关文件 `unrelated.txt` / `other.log` 不进入警告。无这些文件时不警告。`schtasks /query` 对不存在的 `keep-awake-strong`、`keep-awake-bootcheck` 及另一假任务名均返回布尔 false，且在 `ErrorActionPreference=Stop` 下不抛错。没有创建真实计划任务，因此「任务存在时会警告」只核对了查询失败不误报，没有做正向注册。
- 入口 `status` 与缺省命令都调用 `Invoke-Status`。未发现测试文件，没有测试造假证据。

验证方式：从原文件 AST 提取 `Invoke-Status`、`Test-WatcherRunning`、`Get-LegacyArtifacts`、`Test-TaskRegistered` 原文，状态路径全部改到 TEMP。守护进程用临时目录里名为 `awake-watcher.ps1` 的睡眠进程代替，没有启动仓库里的真实守护进程，没有调用防睡眠 API。电源三态是注入到 `Get-PowerLine` 的返回值，不是拔插电池实测。审查前后 `%USERPROFILE%\.keep-awake` 仍只有 `awake-watcher.log`（1776 字节，2026-10-15 06:37:34.341）。`keep-awake.ps1` SHA-256 仍为 `A7C5DC4F4BEC25F7447E9FF5EB806826C3CF748E4F34BC9AC9268C66686ACD2C`。

## 第 2 遍

PASS — 两个原反例都不再抛 null 错误：零字节 state 显示「守护进程运行中（状态: ）」，零字节 pid 显示「未开启」，没有把 `holding-ac` 当成挡住。

审查时间：2026-10-15 23:06:54。只复核上一轮这一条。实际读取当前 `Test-WatcherRunning`（57–70）与 `Invoke-Status`（370–381）。没有修改代码，没有写 `%USERPROFILE%\.keep-awake`。

- **pid 空文件：修复成立。** `59–62` 先判断 `-Raw` 是否为 `$null`，空则当 `''`，`TryParse` 失败后 `return $false`。隔离复现：pid 长度 0，旁边有 `mode=on` 和 `watcher-state=holding-ac`。原 `Invoke-Status` 无异常，首行是「未开启（正常睡眠行为）」，没有挡住句，也没有 null-valued expression。
- **state 空文件：修复成立。** `374–378` 对 pid 与 state 都先判 `$null` 再 `Trim`；state 为空时 `$st` 保持 `''`，走 default。隔离复现：pid 指向命令行含 `awake-watcher.ps1` 的存活进程，state 长度 0。原函数无异常，输出「守护进程运行中（状态: ）」并带该 PID，没有写成挡住。

验证边界：AST 提取原文后在 TEMP 执行。`Get-LegacyArtifacts` 仅用返回空数组的桩，避免夹具缺函数；它在状态句之后调用，不参与这次空文件判定。未启动真实守护进程。`keep-awake.ps1` SHA-256 现为 `4F5DA736E489A25E4AEB2C0AA0B1F8455335D97D486DA5B091F16049501F2FEF`，与上一轮不同是因为该修复已写入；本轮审查前后哈希不变。真实状态目录清单审查前后一致。
