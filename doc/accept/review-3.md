BLOCKING

审查对象：`scripts/keep-awake.ps1` 的 `Stop-Watcher`（115–132）、`Invoke-Off`（300–306）及入口 `'off' { Invoke-Off }`（339）。对照 `scripts/awake-watcher.ps1` 的 pid/stop 时序。依据 `doc/PRD.md` §3.3、§2、§4 与 `TASKS.md` 条目 3。审查时间：2026-10-15 02:08:06。只报告需求、实现及指定边界的阻断项。没有修改代码，没有读写 `%USERPROFILE%\.keep-awake`。

1. **scripts/keep-awake.ps1:123–131、300–305、339 — 强制停止失败被静默吞掉，仍宣称守护进程已停，并删掉 pid 与 stop。** 注释写的是“仍活着才强杀”，条件却只是 pid 文件还在。`Stop-Process -Force` 使用 `SilentlyContinue`，返回后不检查进程是否退出；无论解析失败、拒绝访问还是进程仍在，都删除 pid 文件，最后无条件删除 stop。`Invoke-Off` 不看停止结果，删除状态文件后固定输出“守护进程已停，恢复正常睡眠”，入口也不 `exit 1`。守护进程因此可以继续持有并重新发布 `holding-ac`，而下一轮 `off` 已经看不到 pid 和 stop。**依据：PRD §2“清理失败 → 如实报告，不静默吞掉”；§3.3“停守护进程、删 mode/info/watcher-state”；§4“off 一定放开”；TASKS 条目 3；审查指定的“强制停止失败被静默”和“off 时守护进程恰在发布状态”。**
   - 隔离复现 A（真实 `Stop-Process`）：TEMP pid 文件内容为 `4`。System 进程在调用前后都存在，说明强杀失败。原 `Stop-Watcher`/`Invoke-Off` 耗时 8213ms，无异常，输出成功句，pid、stop、mode、watcher-state 均被删除。
   - 隔离复现 B（同一用户进程无法让真实 `Stop-Process -Force` 失败，故只把 `Stop-Process` 换成发出非终止错误、且不结束进程的同签名函数；`Stop-Watcher`/`Invoke-Off` 文本未改）：发布进程 PID 32816 持续写 `holding-ac`。标记文件记录 `denied 32816`。耗时 8156ms，无异常，输出成功句；pid 与 stop 被删除，mode 被删除，但 700ms 后 `watcher-state` 仍为 `holding-ac`，发布进程仍在，日志在 off 返回后继续出现 publish。
   - 这不是要求系统 API 永远能杀死进程，而是失败后仍报告已停止，并销毁之后还能识别/通知该进程的文件。

2. **scripts/keep-awake.ps1:117–127，对照 57–69 — 守护进程已死或 pid 已被复用时，不校验归属，等满约 8 秒后强制结束 pid 文件里的进程。** 等待条件是 pid 文件存在，不是进程仍是 `awake-watcher.ps1`。同文件 `Test-WatcherRunning` 已要求命令行匹配，匹配失败或无法确认时返回 false；`Stop-Watcher` 完全不调用它。残留 pid 指向普通用户进程时会被杀掉，然后仍输出成功。残留 pid 恰好是本次 `off` 进程时，`off` 在清理前杀死自己。**依据：PRD §3.3 只要求停守护进程，不授权结束其他进程；§4 幂等要求无守护进程时 off 安全；§2 不得假装已停止；审查指定的“守护进程已死但 pid 文件残留”和“stop 哨兵残留”。**
   - 隔离复现 A（真实 `Stop-Process`）：TEMP pid 指向 `pwsh -NoProfile -Command Start-Sleep -Seconds 120`。调用前 `Test-WatcherRunning` 为 false，进程存活。原函数耗时 8169ms 后该进程已死，无异常，输出成功句，pid/stop/mode/watcher-state 被删。命令行不含 `awake-watcher.ps1`。
   - 隔离复现 B（真实 `Stop-Process`，子进程 pid 文件写入自己的 `$PID`）：子进程写出 entered 后执行原 `Invoke-Off`，未写出 survived。退出码 -1。stop 内容仍为 `stop`，pid、mode、`watcher-state=holding-ac` 都还在。没有成功句，也没有失败说明；规定要删的文件没删完，哨兵残留。
   - 不把“8 秒偏慢”单独当阻断；阻断是盲杀和自杀后的不完整、不诚实收场。

3. **scripts/keep-awake.ps1:304–305 — 规定删除的状态文件删除失败被静默，仍宣称成功。** `Remove-Item` 对 mode/info/watcher-state 使用 `SilentlyContinue`，随后无条件输出成功句。文件被占用时 mode 可以留下来，info 与 watcher-state 仍被删掉，调用方看不到失败。**依据：PRD §3.3“删 mode/info/watcher-state”；§2“清理失败 → 如实报告，不静默吞掉”。**
   - 隔离复现：TEMP 中三个文件都存在，仅 mode 以 `FileShare.None` 独占打开。直接 `Remove-Item` 的错误是文件被另一进程占用。原 `Invoke-Off` 无异常并输出成功句；mode 仍在，info 与 watcher-state 已消失。
   - 这是删除失败被吞掉，不是“状态文件本来就缺”。部分缺失的对照见下方，那条不是阻断。

4. **scripts/keep-awake.ps1:117、131、305；scripts/awake-watcher.ps1:54–111、127 — pid 文件不存在时不武装 stop，还会删掉已有哨兵，然后宣称已停。** `Stop-Watcher` 只在 pid 文件存在时创建哨兵；函数末尾总是删除 stop。守护进程在 `Add-Type`（54–55 起）和取得互斥锁之后才写 pid（111），主循环才检查哨兵（127）。因此启动后、写出 pid 前的 `off` 不会留下哨兵。问题 1 已证明失败的强杀会先删掉 pid 和 stop 而进程仍在；此时再执行 `off` 走的就是这条路径，仍然报告已停。**依据：PRD §3.3“停守护进程”；§4“最后一次命令生效，off 一定放开”。**
   - 隔离复现：无 pid 时原 `Invoke-Off` 不创建 stop，输出成功句，无异常。预先放好的 stop 在无 pid 时被删除，耗时 1ms，同样输出成功句，没有尝试结束进程。
   - 这是原函数控制流加守护进程源码时序，不是对真实守护进程做的并发 on/off 端到端。时序本身已使“先 off、后写 pid”的守护进程看不到哨兵。

对照核验（这些路径未构成阻断）：
- 守护进程正在发布状态且遵守哨兵：TEMP 子进程先写 `holding-ac`（02:06:19.200），216ms 后看到 stop，自行删 pid 并写退出标记。原 `Invoke-Off` 耗时 332ms，强杀次数为 0，mode/info/watcher-state/pid/stop 均不存在，子进程已退出。优雅路径不会把“发布中”误判成停不掉，也不会留下 `holding-ac`。
- 状态文件部分缺失：只有 mode、只有 info+watcher-state、三者都不存在，原 `Invoke-Off` 均无异常；存在的文件被删，不创建新文件，并输出成功句。无守护进程时的幂等删除成立。
- 不动电源计划、不创建 settings、无残留时不提权：`Stop-Watcher` 与 `Invoke-Off` 函数体没有 `powercfg`、`RunAs`、`settings.json`。`Invoke-Off` 会调用 `Invoke-LegacyCleanup` 和 `Remove-LegacyHooks`（隔离桩被各调用 1 次，桩不提权）。真实清理函数在 140 行于残留数为 0 时返回，`RunAs` 在 195 行，无残留到不了提权。钩子函数对不存在的 settings 直接 `continue`。本轮不审这两个函数的内部清理逻辑，也没有执行它们，因此没有弹 UAC，也没有改真实 settings。
- 入口接线：339 行 `'off'` 调用 `Invoke-Off`。未发现测试文件，没有测试造假证据。

验证方式与范围：
- 从原文件 AST 提取 `Stop-Watcher`、`Invoke-Off`、`Test-WatcherRunning` 的原文执行，状态文件全部在独立 TEMP 目录。
- 首轮有 3 个子进程因 `Start-Process` 未引用含空格路径而以退出码 64 立即失败；该轮的 graceful、self-kill、republish 作废，不计入结论。有效动态证据来自进程内原函数调用，以及修正引号后的重跑。
- 未启动或停止真实 `awake-watcher.ps1`，未调用防睡眠 API，未写 `%USERPROFILE%\.keep-awake`。审查前后该目录仍只有 `awake-watcher.log`（1554 字节，2026-10-15 01:30:14.608）。
- 未做真实 UAC 对话框观察；无残留不提权的结论来自上述提前返回，不是交互桌面实测。

被审文件审查前后 SHA-256 均为：`keep-awake.ps1` `2A59C09A53066F0164562CC8B8EFD914D872BCB27824AD77BCA4FF8EA46ABC42`，`awake-watcher.ps1` `06445F6CE9208FB98A60C7A4A675C9D41572DCFF083B359AD476A2A871D99F41`。只新建本报告，不修改代码、TASKS 或其他记录。

## 第 2 遍

PASS — 上一轮 4 条反例已被当前 `Stop-Watcher` / `Invoke-Off` 消除；强杀失败会 exit 1 并留下 pid 与哨兵，外来 pid 与自身 pid 不再被杀，锁定的 mode 会点名失败，无 pid 时哨兵保留。

审查时间：2026-10-15 22:56:38。只核对上一轮 4 条及其直接路径。实际读取当前 `scripts/keep-awake.ps1` 的 `Stop-Watcher`（115–171）与 `Invoke-Off`（340–361）。没有修改代码，没有写 `%USERPROFILE%\.keep-awake`。

1. **强杀失败不再报成功。** `158–164` 只在归属成立后 `Stop-Process`，再用 `Get-Process` 确认；仍在则 `return $false`，不删 pid/stop。`342–346` 收到 `$false` 输出「OFF 未完成」并 `exit 1`，不进入状态文件删除。隔离复现：命令行含 `awake-watcher.ps1` 的进程 PID 25528 持续运行，`Stop-Process` 桩只记 `denied 25528` 且不结束进程。子进程退出码 1，主机日志依次为强制停止失败、OFF 未完成，没有成功句；pid 与 stop 仍在，mode/info/`watcher-state=holding-ac` 仍在，旧清理与钩子函数未被调用，进程仍活。原 PID 4 反例现在不进入强杀：System 仍在，杀进程日志为空，退出码 0。这是问题 2 的外来 pid 路径，不是强杀失败被吞掉。

2. **不再盲杀、不再自杀；已死 pid 不再等 8 秒。** `154–156` 要求解析成功、`id -ne $PID` 且命令行含 `awake-watcher.ps1` 才杀。`133–135` 对已死进程直接清理并 `return $true`。隔离复现：sleeper 命令行为 `pwsh -Command Start-Sleep`，不含 `awake-watcher.ps1`，结束后仍活，杀进程日志为空，退出码 0。self-kill 子进程写入自己的 `$PID` 后仍写出 survived，退出码 0，没有被杀死。已结束进程的残留 pid 耗时 60ms，返回 true，未调用 `Stop-Process`，pid 与 stop 已删。

3. **状态文件删除失败会点名并 exit 1。** `351–360` 删后逐个 `Test-Path`，仍在则列出文件名并 `exit 1`，不输出成功句。隔离复现：mode 以 `FileShare.None` 独占打开。子进程退出码 1，主机日志为「OFF 未完全完成… mode」，没有成功句；mode 仍在。未锁定的 info 与 watcher-state 被删掉，不改变「失败已被报告、未假装成功」这一条。只有 mode、info/state 缺失时退出码 0，不把缺失当失败。

4. **无 pid 时先武装哨兵并保留。** `122` 无条件写 stop；`139–141` 等到约 3 秒，仍无 pid 则 `return $true` 且不删哨兵。隔离复现：无 pid 耗时 3070ms，返回 true，stop 内容为 `stop`。预先放的旧哨兵被覆盖为 `stop` 后仍在，不再被删掉。pid 在窗口内出现（go 后 429ms 写出）时走优雅等待：耗时 854ms，未强杀，子进程看到哨兵后自删 pid，哨兵随后被删。pid 已经存在且守哨兵时耗时 22ms，同样不强杀、确认退出后才删哨兵。`awake-watcher.ps1:111` 写 pid 之后、`127` 才检查哨兵，持有调用在该检查之后；晚启动进程会先看到保留哨兵再退出。这一点只核对问题 4 修复所依赖的时序，不重审守护进程。

验证边界：原函数文本由 AST 提取后在 TEMP 执行。强杀失败仍用同签名、只发出非终止错误的 `Stop-Process` 桩，因为同一用户的匹配进程无法让真实 `Stop-Process -Force` 失败。未启动真实守护进程，未调用防睡眠 API。本轮审查前后 `%USERPROFILE%\.keep-awake` 仍只有 `awake-watcher.log`（1776 字节，2026-10-15 06:37:34.341）。`keep-awake.ps1` SHA-256 仍为 `A7C5DC4F4BEC25F7447E9FF5EB806826C3CF748E4F34BC9AC9268C66686ACD2C`。
