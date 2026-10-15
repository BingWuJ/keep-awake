BLOCKING

1. **scripts/keep-awake.ps1:105、scripts/keep-awake.ps1:263；依赖 scripts/awake-watcher.ps1:101、scripts/awake-watcher.ps1:118** — 启动成功只检查 PID 对应进程存在，没有确认守护进程已进入 `holding-ac`；`Invoke-On` 仅凭自己读取的 `Online` 就写入 `mode=on` 并输出“挡住系统空闲睡眠”。守护进程在读取电源和调用防睡眠 API 之前已经写入 PID，因此电源读取失败或防睡眠 API 失败时仍可能被父命令判作成功。已有守护进程的状态为 `error-power-unknown` 时，重复 `on` 同样不会检查实际状态。已通过提取原文件函数进行隔离模拟验证：电源返回 `Online`、进程判定为存在、状态文件为 `error-power-unknown`，`Invoke-On` 仍正常返回并输出“挡住系统空闲睡眠”，实际状态文件保持错误状态。**依据：PRD §3.1（插电时启动并挡系统空闲睡眠）；§2（读不到电源状态 → 不挡并报错）；TASKS.md 条目 1（插电 exit 0 且守护进程 holding-ac）。**

2. **scripts/keep-awake.ps1:65、scripts/keep-awake.ps1:66；调用处 scripts/keep-awake.ps1:254** — 读取进程命令行失败或返回空值时，`Test-WatcherRunning` 直接返回 `$true`，没有确认 PID 对应的是本工具守护进程。残留 PID 被其他进程复用且 CIM 查询失败时，`on` 会跳过启动、写入开启状态，并宣称正在挡睡眠，实际没有守护进程。已通过提取原文件函数进行隔离模拟验证：临时 PID 文件指向本次审查 PowerShell 进程，CIM 查询抛错，`Test-WatcherRunning` 返回 `True`；`Invoke-On` 输出“已在运行”和“挡住系统空闲睡眠”，写入 `mode=on`，但不存在 `watcher-state`。**依据：PRD §3.1（插电时启动守护进程挡系统空闲睡眠、重复 on 幂等）；TASKS.md 条目 1（插电 exit 0 且守护进程 holding-ac）。**

未验证：未进行真实插拔电源、真实防睡眠 API 失败、守护进程启动失败或并发重复 on 的端到端测试；上述动态复现为隔离函数模拟，不是实际生产环境故障复现。未发现测试文件，但未据此对全部历史验收记录是否真实作出判断。

## 第 2 遍

BLOCKING — 问题 2 已修复；问题 1 的状态分支已修复，但仍可能把旧守护进程遗留的 holding-ac 当作本次启动成功，原“未确认实际状态就宣称挡住睡眠”问题未完全消除。

审查时间：2026-10-15 00:31:04。范围仅限前述两条修复及其直接影响；没有修改代码，没有提出增强类意见。

1. **问题 1：部分修复，仍阻断。** 当前 `scripts/keep-awake.ps1:264–286` 确实轮询状态文件，并按守护进程发布值分支；隔离调用从原文件 AST 提取的 `Invoke-On`，模拟本进程电源为 `Online`：
   - `holding-ac`：退出 0，输出“挡住系统空闲睡眠”。
   - `released-battery`：退出 0，明确提示未挡。
   - `error-power-unknown`：退出 1，明确提示“当前未挡”。
   - 非预期值、文件不存在：退出 1，输出“不能确认在挡”。文件不存在路径走实际 4 秒等待，没有把错误状态判成成功。

   **残留阻断：状态没有与本次启动关联。** `Start-Watcher:88–109` 启动前不清除旧 `watcher-state`；`Invoke-On:267–269` 读取到任何非空文本立即停止等待，`274–275` 对遗留 `holding-ac` 直接输出成功。旧守护进程异常退出留下此状态后，新进程只要已写 PID、尚未发布自己的状态，父命令即可误报。与原报告依赖点一致，`awake-watcher.ps1:101` 仍先写 PID；首次 API 返回 0 时，`119–125` 又只在 `$Holding` 已为真时发布错误，初始 `$Holding=$false`（106 行）会保留旧状态。因此这个假成功不只是输出措辞问题，实际未持有时仍可能退出 0。

   **复现证据：** 从原文件 AST 原样提取 `Invoke-On`、`Start-Watcher`、`Test-WatcherRunning`、`Get-Now`，将全部状态路径改绑到 TEMP 独立目录；预置遗留 `watcher-state=holding-ac`。仅模拟外部依赖：电源读数为 Online；启动前无可确认进程；模拟 Start-Process 写入新 PID，之后 CIM 返回新进程的 watcher 命令行，但新进程不发布状态（对应启动发布前窗口，或上述首次 API 失败路径）。未真实启动守护进程、未调用防睡眠 API、未停止任何实际进程。
   结果：`started=True`、状态仍为预置的 `holding-ac`、输出“ON：插电中，挡住系统空闲睡眠”、**退出 0**。此复现使用原始三个生命周期/判定函数，不是重写被审逻辑；仅验证问题 1 的完成条件仍有反例。

2. **问题 2：修复成立。** `scripts/keep-awake.ps1:67–69` 的 CIM 异常变为 `''`，随后执行命令行匹配；异常、空查询结果、空 CommandLine 均返回布尔 `False`，不再因本进程能读到 PID 或 Get-Process 成功就返回真。`64–66` 的注释明确说明 ownership 无法确认时不能假成功。对原始 `Test-WatcherRunning` 做隔离模拟：Get-Process 成功，CIM 分别抛错、返回空结果、返回空命令行、返回其他进程命令行，均得 `running=False; type=Boolean`；正常 watcher 命令行得 `running=True; type=Boolean`。这些模拟子进程本身退出 0，指测试正常执行，**不是把 False 当成 on 成功**。这条修改未发现范围内新增阻断缺陷。

验证边界：共 11 个隔离案例；脚本语法解析通过。未进行真实插拔电源、真实 API 失败、真实启动或并发端到端测试。除上述问题 1 残留路径外，不扩展审查其他命令或历史实现。被审脚本 SHA-256 在审查前后均为 `8F5E9524D06D8D3A2F29E133A3118CC822460DC5501EBE69927961D2D58D799C`。


## 第 3 遍

BLOCKING — 第 2 遍的遗留 holding-ac 假成功反例已修复，但明确要求的“空值继续等”未实现：空状态文件使 Invoke-On 的 .Trim() 抛错，未等到终态或 8 秒超时便退出 1。本结论仅针对同一条启动状态确认修复，不扩展审查范围。

审查时间：2026-10-15 00:53:23。实际完整读取两个脚本及第 2 遍记录；两个脚本语法解析通过。没有修改代码，没有提出增强类意见。

### 四项修复核验

1. **启动前清理旧状态：成立。** `keep-awake.ps1:92–94` 包含 stale holding-ac must not count 的说明并删除 StateOut，删除发生在 Start-Process 之前。隔离启动桩在被调用时确认旧状态文件已经不存在。
2. **写 PID 后发布 starting：成立。** `awake-watcher.ps1:101–104` 写 PID 后立即调用原有 Set-PublishedState 发布 starting，位于首次电源判断/API 调用之前。
3. **首次 API 失败发布错误：成立。** `awake-watcher.ps1:121–127` 的错误发布已经移出 Holding 条件；Holding=false 时也会执行。提取原始电源分支及 Set-PublishedState 函数，以同签名的内存 Native 测试桩返回 0，结果为 `holding=False; state=error-power-unknown`。没有调用真实 Windows 防睡眠 API。
4. **只认终态与等待窗口：部分成立。** `keep-awake.ps1:269–275` 将窗口改为 8 秒，只有 holding-ac、released-battery、error-power-unknown 会结束等待，starting 会继续等待；**空文件路径仍不成立**，见下面的阻断项。

### 第 2 遍反例回归及终态验证

方法：由原文件 AST 原样提取 Invoke-On、Start-Watcher、Test-WatcherRunning、Get-Now；状态路径全部改绑到独立 TEMP 目录。每个父命令案例预置旧 watcher-state=holding-ac，启动前模拟无已确认进程；启动桩只写新 PID，之后 CIM 返回该新 watcher 的命令行。外部依赖由桩提供，未真实启动/停止守护进程。

|隔离案例|实际结果|
|---|---|
|清除旧 holding-ac，新进程只写 PID，不发布状态|退出 1，输出“不能确认在挡”；子进程总耗时 8.54 秒|
|清除旧 holding-ac，新进程写 PID 与 starting，始终无终态|退出 1，输出“不能确认在挡”；子进程总耗时 9.55 秒|
|starting → holding-ac|等待新终态后退出 0，输出正在挡|
|starting → released-battery|等待新终态后退出 0，明确提示未挡|
|starting → error-power-unknown|等待新终态后退出 1，明确提示当前未挡|
|新进程写 PID，状态文件存在但为零字节，模拟预定后续轮询发布 holding-ac|0.64 秒内退出 1，报 null-valued expression；在预定终态发布之前已终止|
|原始 watcher 分支，Holding=false 且 API 测试桩返回 0|发布 error-power-unknown，Holding 仍为 false|

以上耗时是整个模拟子进程耗时，包含 PowerShell 启动开销，不等同于纯轮询计时。前两个案例没有重现原 exit 0 假成功。

### 范围内阻断项：空值没有继续等待

**位置：scripts/keep-awake.ps1:273。** 零字节文件上的 `Get-Content -Raw` 返回 `$null`，随后的 `.Trim()` 抛出“ You cannot call a method on a null-valued expression.”；外层 ErrorActionPreference=Stop，Invoke-On 没有捕获，因此立即终止。它既没有继续等待后续真实终态，也没有到超时 default 分支输出“不能确认在挡”。

复现是上述零字节状态文件案例，真实执行原始读取与轮询代码，没有模拟 Get-Content 或重写判定逻辑。模拟桩原计划在启动后的第二次 250ms 轮询等待时写入真实 holding-ac；命令却在首次读取空文件时已抛错，未走到该轮询。此边界与此次明确修复要求“starting 与空值继续等”直接对应；原 Set-PublishedState 使用 Set-Content 写状态文件，文件存在与读到完整内容并非同一条件。

未验证：真实启动、真实电源切换、真实 API 失败及并发端到端行为。未审查其他命令、清理逻辑或提出额外功能建议。

代码未修改；前后 SHA-256 一致：
- keep-awake.ps1：`4F41B27848F7970A4ADB56FF7A9CCF4D5C5D8F5B178AC83713F6FF509ED5C2EE`
- awake-watcher.ps1：`BE97A4629B0DE7CC990F5C328FAE542C205C08D7530B0B57B2102C26FF09AA78`


## 快速回归

PASS — 从原文件提取 Invoke-On 做零字节状态文件隔离模拟，确认继续经过两次轮询等待，在桩发布 holding-ac 后输出成功并退出 0，未出现 null-valued expression；代码未修改，本结论仅覆盖该回归点。
