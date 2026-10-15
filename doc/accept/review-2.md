BLOCKING

审查对象：scripts/awake-watcher.ps1 全文；依据实际读取的 doc/PRD.md §3.2、§2 与 TASKS.md 条目 2。审查时间：2026-10-15 01:08:40。只报告需求、实现及边界阻断项，不提出增强类意见；没有修改代码。

1. **scripts/awake-watcher.ps1:121–127、135–140、142–147 — 重申 API 失败时没有释放既有持有，之后拔电也可能跳过释放。** 持有成功后，60 秒重申若返回 0，代码只把 Holding 设为 false 并发布 error-power-unknown，没有调用 ClearState。变量改为 false 并不清除线程已有的 ES_SYSTEM_REQUIRED；随后 Offline/Unknown 分支又因 Holding=false 跳过释放。**依据：PRD §3.2“API 返回失败 → 释放并标记错误”“拔电 → 立即释放”；§2“电池上不挡睡眠”；TASKS 条目 2“unknown/API 失败释放并标记”。**
   - 隔离复现：原主循环与 finally 原样执行，逻辑时间每轮推进 5 秒；Native 桩第一次持有成功，60 秒重申失败（返回 0 且不改变既有标志），65 秒电源变为 Offline。
   - 在 60 秒快照：实际模拟标志 active=true，发布 error-power-unknown，API 调用列表只有两次 0x80000001，没有 0x80000000 清除调用。
   - 在 65 秒快照：active 仍为 true，已发布 released-battery，调用列表仍没有清除调用。直到人为发 stop 进入 finally 才释放；守护进程继续运行时的需求已违反。
   - 这里没有把“失败一定自动释放”当作 API 保证；失败不能证明旧标志已清除，原代码也没有执行 PRD 要求的释放动作。

2. **scripts/awake-watcher.ps1:136–140、143–147 — 释放 API 的失败返回值被丢弃，仍宣称已释放。** Offline 和 Unknown 分支把 ClearState 调用结果赋给 null，无条件把 Holding=false 并发布 released-battery 或 error-power-unknown。释放返回 0 时，程序继续运行且不再知道旧持有仍可能存在；之后 Unknown/Offline 又会跳过清除。**依据：PRD §3.2“拔电/读不到 → 释放”“API 返回失败 → 释放并标记错误”；§2“电池上不挡睡眠”“失败必须诚实”；TASKS 条目 2。**
   - 隔离复现：Online 持有成功 → Offline 清除 API 返回 0 → Unknown。
   - Offline 快照：active=true，却发布 released-battery；Unknown 快照：active 仍为 true，清除调用次数没有增加。原循环继续执行，没有因释放失败发布针对该失败的错误或如实保留未确认释放的状态。
   - 此项与问题 1 不同：问题 1 根本未调用释放；本项已经调用但未检查失败。

3. **scripts/awake-watcher.ps1:90–101、152–157 — 将所有 WaitOne 异常当作弃用锁并宣称已取得所有权，破坏单实例边界。** catch 没有区分 AbandonedMutexException；任何等待异常都会使 Owned=true，随后写 PID、发布状态、调用持有 API。非弃用异常没有证明取得互斥锁，却执行受锁保护的主循环；finally 还会删 PID 并对未拥有的锁 ReleaseMutex。**依据：PRD §3.2“单实例（Global mutex + pid 文件）”与退出清理要求；审查指定的 mutex 异常边界；TASKS 条目 2“单实例”。**
   - 隔离复现：Mutex.WaitOne 桩抛出非弃用的 InvalidOperationException，未授予所有权；临时 PID 预置 existing-owner。原代码仍执行 0x80000001 持有调用并覆盖 PID，finally 删除该 PID；ReleaseMutex 桩报告 not owned，Dispose 未执行。
   - 对照：WaitOne 返回 false 时，不持有、不删既有 PID，并 Dispose；AbandonedMutexException 时正常接管。缺陷是对非弃用异常的处理，不是否定弃用锁接管本身。
   - 此为异常路径逻辑模拟，不声称已在本机真实 mutex 上制造该异常或运行两个真实守护进程。

4. **scripts/awake-watcher.ps1:40–42、136–140 — 状态发布失败被静默吞掉，可在已经释放后继续对外保留 holding-ac。** Set-PublishedState 对 Set-Content 的失败不作报告或向调用者传播；旧状态不会因发布失败消失。拔电释放成功后若 released-battery 写入失败，状态文件仍是此前 holding-ac，父命令/状态读取方得到“正在挡”的旧终态。**依据：PRD §3.2“拔电 → 释放并标记 released-battery”“状态发布到 watcher-state”；§2“不得假装在挡”“失败必须诚实”；审查指定的状态覆盖边界；TASKS 条目 2。**
   - 隔离复现：Online 持有成功并写 holding-ac → Offline 的清除 API 成功；仅对写入 StateOut 的 released-battery 注入 Set-Content 异常，其他文件操作仍用真实 PowerShell。
   - 下一次轮询快照：active=false、文件内容仍为 holding-ac、主循环无异常并继续运行。Set-PublishedState 的原始 catch 确实吞掉了写失败。
   - 这是实际文件内容与模拟持有状态的对照，不把发布函数调用当作发布成功。

验证方式与范围：
- 由原文件 AST 提取 Write-Log、Set-PublishedState 和完整主 try/finally，不改写状态机。所有状态/PID/日志/stop 文件放在独立 TEMP 目录。
- Windows Native API 使用同签名测试桩，保留原 FlagsAttribute、枚举值及逐调用结果；失败返回 0、不改变之前的模拟标志。Mutex 使用受控桩；电源由序列提供；Get-Date/Start-Sleep 为逻辑时钟与哨兵注入。没有调用真实防睡眠 API、Global mutex，没有启动或停止真实守护进程。
- 首版测试桩漏带 FlagsAttribute 导致枚举转换错误，已修正并清空夹具状态后重跑；该无效轮次不计入结论。最终 10 个案例的结果经断言核验，以上证据只来自最终有效轮次。

对照核验：
- 持有标志为 0x80000001（ES_CONTINUOUS | ES_SYSTEM_REQUIRED），DISPLAY 位为 0；枚举定义含 ES_DISPLAY_REQUIRED 不等于把它加入持有组合。
- 正常 Online → Online → Offline → Online → Unknown 的发布序列为 holding-ac、holding-ac、released-battery、holding-ac、error-power-unknown；正常释放/续挡及 finally 清除、删 PID 均通过模拟。
- 稳定 Online 情况，55 秒仍仅一次持有调用，60 秒出现第二次持有调用；各轮 Start-Sleep 参数为 5 秒。
- 初始存在 stop 或在轮询等待末尾注入 stop 时，下一次循环先检查哨兵并退出，显式清标志、发布 stopped、删 PID、释放/Dispose mutex；这里只验证控制流，不冒充真实约 5 秒退出实测。
- 日志初始超过 256KB 的案例触发轮转，最终日志 267 bytes。
- 未取得测试造假证据；不因本次模拟发现缺陷就认定历史测试记录造假。

未验证：真实插拔电源、睡眠/恢复、真实 API 失败、真实互斥异常及并发运行、真实 60 秒重申/5 秒退出的墙钟端到端行为。以上不影响已经复现的状态机/异常处理反例。

被审代码审查前后 SHA-256 保持为 BE97A4629B0DE7CC990F5C328FAE542C205C08D7530B0B57B2102C26FF09AA78。只新建本报告，不修改代码、TASKS 或其他记录。


## 第 2 遍

BLOCKING — 问题 3 的互斥异常处理和问题 4 的发布重试已修复；问题 1、2 仍会在清除失败后丢失“可能仍持有”的状态，下一轮电池路径跳过清除并误发布 released-battery，原阻断未完全消除。

审查时间：2026-10-15 01:20:40。实际读取当前 awake-watcher.ps1 全文及上一遍报告；仅复核四条修复与直接影响路径，没有修改代码或提出增强类意见。

### 问题 1：部分修复，仍阻断

**位置：scripts/awake-watcher.ps1:138–148、157–170。** 重申失败后确实显式调用 ClearState，并在清除也失败时写“flag may still be held”，本轮发布 error-power-unknown；清除成功的原反例已经通过。但第 139 行在确认清除成功之前就把 Holding=false，清除失败后没有保留这种不确定状态。紧接着 Offline 路径因 Holding=false 进入第 169–170 行，直接发布 released-battery，不再尝试或确认释放。

隔离结果：
- 首次持有成功，逻辑 60 秒重申返回 0、随后清除成功：60 秒 active=false、state=error-power-unknown；65 秒 Offline 后 active=false、state=released-battery。此对照通过。
- 同样的重申失败，但追加清除也返回 0：60 秒 active=true、state=error-power-unknown，日志含 flag may still be held；65 秒 Offline 时 active 仍为 true，却变为 released-battery。
- 两个失败轮次之间 API 调用列表保持为 [0x80000001, 0x80000001, 0x80000000]，下一轮没有新增清除调用。日志承认未确认清除，不能证明下一轮已释放。

**依据：PRD §3.2“API 返回失败 → 释放并标记错误”“拔电 → 释放并标记 released-battery”；§2“电池上不挡睡眠”“失败必须诚实”；TASKS 条目 2。** 阻断在于失败不确定性被下一轮无依据的成功状态覆盖，不是要求系统 API 永远成功。

### 问题 2：部分修复，仍阻断

**位置：scripts/awake-watcher.ps1:158–170、173–182。** Offline/Unknown 的清除返回值现在有检查，失败当轮确实发布 error-power-unknown，没有立刻宣称 released-battery；但第 159/174 行同样提前设 Holding=false。下一轮为 Offline 时，第 169–170 行仍会在没有清除成功依据的情况下发布 released-battery。

两个直接回归：
- Online 持有成功 → Offline 清除返回 0 → 持续 Offline：第一电池轮 active=true、state=error-power-unknown；5 秒后的第二电池轮 active=true、state=released-battery。
- Online 持有成功 → Unknown 清除返回 0 → Offline：Unknown 轮 active=true、state=error-power-unknown；下一 Offline 轮 active=true、state=released-battery。
- 两个案例 API 调用列表均在失败清除后的下一轮保持 [0x80000001, 0x80000000]，没有再次确认释放。

**依据：PRD §3.2 的拔电/Unknown 释放与 API 失败标记要求；§2 电池不持有及失败诚实；TASKS 条目 2。** 与问题 1 残留同源，分别由重申后的清除失败、直接电源转换后的清除失败触发，未另扩大为新条目。

### 问题 3：修复成立

**位置：scripts/awake-watcher.ps1:101–105、200–201。** 只捕获 System.Threading.AbandonedMutexException 后置 Owned=true，其他异常向外传播，Owned 保持 false，finally 只 Dispose。

使用有真实 .NET 方法签名的 Mutex 测试类复核异常类型，避免 PowerShell ScriptMethod 的额外包装混淆 typed catch：
- 非弃用 InvalidOperationException：异常传播；既有 PID 文本 existing-owner 保持；持有/清除 API 调用数均为 0；没有 ReleaseMutex；Dispose=true。
- AbandonedMutexException：正确接管，执行持有流程，退出时清除、删 PID、ReleaseMutex 与 Dispose；没有异常。
- WaitOne=false：既有 PID 保持、不调用持有/清除 API、只 Dispose。

本条未复现上一遍无所有权进入主循环或删除别人 PID 的缺陷。

### 问题 4：所述收敛重试修复成立

**位置：scripts/awake-watcher.ps1:40–50、184–190。** Set-PublishedState 成功/失败分别返回 true/false；写失败有日志；主循环只在成功返回后更新 Published，失败后下一轮重新尝试。

对原反例注入 released-battery 写入异常：
- 一次失败：第一次电池轮已清除持有，文件暂留 holding-ac，发布尝试次数为 1，日志记录失败；下一轮（逻辑 5 秒后）重试成功，文件变为 released-battery，尝试次数为 2。
- 连续两次失败：连续两轮保留旧文件但各有失败日志；第三次尝试成功，文件收敛为 released-battery。
- 没有在发布失败时把 Published 更新为 released-battery，因而不再永久跳过该状态重写。

此结论证明用户描述的“每轮重试，写成功后收敛”逻辑；不把重试期间的旧文件当作已更新，也不声称永久文件系统失败时仍能成功发布。

### 验证范围

最终 9 个有效隔离案例经断言核验。由原文件 AST 提取 Write-Log、Set-PublishedState 和完整主 try/finally，状态机保持原样；全部文件位于独立 TEMP 目录。Native 桩保留 FlagsAttribute 与同名枚举/方法，失败返回 0 不改变既有模拟标志；Mutex 异常测试使用 .NET 方法桩；电源序列和 5 秒/60 秒逻辑时间受控。未调用真实 Windows 防睡眠 API、Global mutex，也未启动/停止真实守护进程。

未验证真实电源切换、真实 API/文件系统故障、墙钟 5 秒/60 秒及并发端到端行为；不扩展检查其他命令或需求。模拟守护进程最后的 stop/finally 能清除标志，不抵销它此前仍运行时误报已释放的反例。

代码前后 SHA-256 一致：8484B956461ADCC3AD4A79E7FEB027EC9C22DC371A8CBD100B59EF6E3618C162。只追加本小节，保留原报告内容。


## 第 3 遍

PASS — 上一遍两个残留反例均已消除：清除失败后保持 Uncertain，每轮电池路径继续清除并发布 error-power-unknown，只有确认清除成功才转 NotHeld、发布 released-battery；限定范围内未发现新增阻断。

审查时间：2026-10-15 01:32:24。实际读取当前 awake-watcher.ps1 全文及第 2 遍小节，仅复核两个残留反例及直接路径，不修改代码、不扩大范围、不提出增强类意见。

1. **重申失败 → 清除失败 → Offline：修复成立。**
   - 代码依据：scripts/awake-watcher.ps1:134–154。此前非 NotHeld 时，assert 失败会显式清除；清除失败进入 Uncertain（149 行），不再提前变成 NotHeld。
   - Offline 分支 160–172 行对 Held/Uncertain 都继续清除，仅成功进入 NotHeld，并以 FlagState 决定错误或 released-battery。
   - 隔离结果：首次持有成功；逻辑 60 秒重申失败，追加 clear 也失败 → FlagState=Uncertain、模拟标志仍持有、发布 error-power-unknown。65 秒 Offline 再次 clear 失败 → 仍为 Uncertain/error，调用列表新增一个 0x80000000。70 秒持续 Offline 再次 clear 成功 → NotHeld、模拟标志已释放，才发布 released-battery。
   - 60/65/70 秒的 API 调用数量依次为 3/4/5，确认后续轮次没有跳过清除，也没有提前报已释放。

2. **Offline 清除失败 → 持续 Offline：修复成立。**
   - 代码依据：scripts/awake-watcher.ps1:159–172。失败设置 Uncertain，下一轮仍满足非 NotHeld 条件。
   - 隔离结果：Online 持有成功；逻辑 5 秒首次电池清除失败，10 秒电池清除再次失败 → 两轮均 Uncertain/error-power-unknown，模拟标志仍持有；15 秒第三次清除成功 → NotHeld/released-battery、模拟标志释放。
   - 清除调用逐轮增加，失败阶段没有发布 released-battery。

直接路径对照：
- **Unknown 清除重试（174–184 行）：** Online → Unknown clear 失败 → 持续 Unknown clear 失败 → Offline clear 成功；失败期间保持 Uncertain/error，最后确认成功才发布 released-battery。
- **Uncertain 后插回 Online（134–139 行）：** 即使距最近成功 assert 不满 60 秒，也因非 Held 重新 assert；成功后进入 Held 并发布 holding-ac，不会仅凭插电读数改成成功。
- **持续清除失败：** 连续三个电池轮次各执行一次 clear，始终保持 Uncertain/error；没有无依据的 holding-ac 或 released-battery。
- **finally 清除失败（198–200 行）：** 返回 0 时实际日志包含 final clear FAILED；验证只确认用户所述的返回值检查与失败日志，不将模拟线程退出后的标志行为当作真实 Windows 结果。

验证：最终 6 个隔离案例全部经断言核验；源码语法解析通过。由原文件 AST 原样提取 Write-Log、Set-PublishedState 及完整主 try/finally；Native/Mutex 为同签名 .NET 测试桩，FlagsAttribute 和枚举值保持；模拟 API 返回 0 不自动改变既有标志；电源与逻辑时间受控，每轮等待参数为 5 秒。所有 PID、stop、状态、日志文件均位于独立 TEMP 目录，没有调用真实防睡眠 API/Global mutex，没有启动或停止真实守护进程。

未验证真实电源切换、真实 API 失败、真实 60 秒重申/5 秒轮询及并发端到端行为；本 PASS 仅针对本次指定的两个残留反例及直接路径，不构成条目之外的全量验收。

代码前后 SHA-256 一致：06445F6CE9208FB98A60C7A4A675C9D41572DCFF083B359AD476A2A871D99F41。仅追加本小节，保留原报告字节。
