BLOCKING

审查对象：`scripts/statusline.ps1` 全文。依据 `doc/PRD.md` §3.7 与 `TASKS.md` 条目 7。审查时间：2026-10-15 23:52:44。只报告需求、实现及指定边界的阻断项。没有修改代码，没有写 `%USERPROFILE%\.keep-awake`。

1. **scripts/statusline.ps1:22–28、33 — 进程还在就当守护进程活着，不核对命令行，pid 复用时输出 Awake。** `Test-WatcherRunning`（`keep-awake.ps1:64–68`）要求命令行含 `awake-watcher.ps1`，查不到就当未运行。statusline 只 `Get-Process`，然后按 `watcher-state` 显示。**依据：审查要求“命令行不符必须显示 stale，不得显示 Awake”；并与 fail-closed 的归属校验一致。PRD §3.7 的 `● Awake (AC)` 只对应 holding-ac 的本工具守护进程。**
   - 隔离复现：`mode=on`，pid 指向 `pwsh -Command Start-Sleep`（命令行不含 `awake-watcher.ps1`），状态文件为 `holding-ac`。输出 `● Awake (AC)`，退出码 0。不是 `⚠`。

2. **scripts/statusline.ps1:32–37 — 零字节 watcher-state 不输出任何一行；状态文件缺失时输出规格外的 `● Awake`。** 零字节文件 `-Raw` 得到 `$null`，`.Trim()` 在本脚本的 `SilentlyContinue` 下没有变成可见错误，`$st` 为 `$null`。PowerShell 的 `switch ($null)` 不进入 default，于是没有 `Write-Output`。文件不存在时 `$st` 为 `''`，default 输出 `● Awake`，既不是 `● Awake (AC)`，也不是 `⚠`。**依据：PRD §3.7 与 TASKS 条目 7“只读文件输出单行四态”；审查指定的零字节/状态文件缺失边界；不得用 Awake 冒充未确认的挡住状态。**
   - 隔离复现：`mode=on`，pid 指向命令行含 `awake-watcher.ps1` 的存活进程，`watcher-state` 长度 0。标准输出为空，标准错误为空，退出码 0。
   - 同一进程、不创建 `watcher-state`：输出 `● Awake`。

对照核验（未单独构成阻断）：
- 无 mode 或 mode 不是 `on`：`○ Sleep OK`。零字节 mode 也是这一行，没有抛错。
- 有合法进程时：`holding-ac` → `● Awake (AC)`；`released-battery` → `◐ Awake idle (battery - not held)`；`error-power-unknown` → `⚠ Awake error (power unknown - not held)`。
- pid 不存在、pid 为已死数字、零字节 pid：都是 `⚠ keep-awake stale (on, daemon dead)`，没有显示 Awake。
- 向 stdin 写入文本后，`holding-ac` 仍只输出规定的一行。脚本不读 stdin，无提权，不创建状态目录。
- 未发现测试文件，没有测试造假证据。

验证方式：子进程把 `USERPROFILE` 指到 TEMP 后执行原 `statusline.ps1`。审查前后真实状态目录清单一致（仍只有 `awake-watcher.log`，1776 字节，2026-10-15 06:37:34.341）。`statusline.ps1` SHA-256 为 `AA2F7A3100C63E2F0D6A6F17757A2A3346623E7748D82B4815432440BEB4C941`。

## 第 2 遍

PASS — 两个原反例都已消除：外来 pid 显示 stale；零字节和缺失的状态文件都只输出一行 ⚠，不再是裸 Awake。

审查时间：2026-10-15 23:55:59。重新读取当前 `statusline.ps1`。本轮 SHA-256 为 `D7D5700938063879F444749CD0A3AEB75F2A75A1EB1C815469F38C7D88F9C367`，与上一轮不同。没有修改代码，没有写真实状态目录。

1. **pid 复用成立。** `37–41` 行用 CIM 命令行判断，必须含 `awake-watcher.ps1`，否则当未运行。隔离复现：`mode=on`，pid 指向 `pwsh -Command Start-Sleep`，状态文件为 `holding-ac`。输出一行 `⚠ keep-awake stale (on, daemon dead)`，退出码 0，没有 Awake。
2. **空状态与缺失状态成立。** `20–23` 行把零字节读成空串。`50` 行 default 输出 `⚠ keep-awake (state: )`。隔离复现：pid 指向命令行含 `awake-watcher.ps1` 的存活进程。零字节 `watcher-state` 和文件不存在都各输出一行该 ⚠，退出码 0，不是 `● Awake`。
