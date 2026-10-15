BLOCKING

审查对象：`scripts/keep-awake.ps1` 的 `Invoke-LegacyCleanup`（180–256）、`Get-LegacyArtifacts`（80–87）、`Test-TaskRegistered`（74–77）。依据 `doc/PRD.md` §3.5、§2 与 `TASKS.md` 条目 5。审查时间：2026-10-15 23:18:21。只报告需求、实现及指定边界的阻断项。没有修改代码，没有弹 UAC，没有调用会改电源计划的 `powercfg`。

1. **scripts/keep-awake.ps1:207–211、229、235–241 — 恢复失败被吞掉，仍宣称已按备份恢复。** 生成的 `powercfg` 行把错误接到 `Out-Null`，不看 `$LASTEXITCODE`。`restored` 在生成时就写成“有没有拼出行”，不是恢复是否成功；父函数只认提权进程退出码 0 加结果文件存在，不读 `restored`。残留文件清零后固定输出「电源计划已按备份恢复」。**依据：PRD §3.5“按备份恢复”；§2 与审查要求“恢复失败必须如实报告，不得静默吞掉、不得假装已清理”。**
   - 隔离复现：只有 `strong`、没有备份，以及备份 JSON 损坏，原函数都输出该成功句并返回 true。`LIDACTION` 整项为 null 时不生成该项的 `powercfg`，但仍因 scheme 存在把 `restored` 写成 `$true`。`ac` 为 null、`dc` 为 300 时，生成的交流电行是 `...f2b67b1f44da  2>&1 | Out-Null`，索引空缺。
   - 用同签名函数挡住 `powercfg`（返回失败且不调用真实程序）执行生成文本：8 条设置命令和 `/setactive` 都发出，结果文件仍是 `{"restored":true}`。生成脚本没有 `exit`。对照同结构的 `cmd /c exit 1 2>&1 | Out-Null` 后写文件，`pwsh -File` 退出码为 0。因此父函数会把恢复失败判成成功。

2. **scripts/keep-awake.ps1:234、248–251 — UAC 取消或提权脚本非 0 时，先删掉 `strong-result.json`，再报告残留仍在。** 结果文件在 `Start-Process -Verb RunAs` 之前就被删除。取消或退出码 1 的分支不会把它写回。**依据：PRD §3.5“失败（含 UAC 取消）保留残留并如实报告”。**
   - 隔离复现：预置 `strong`、备份和 `strong-result.json`。`Start-Process` 桩抛出取消，不弹真实 UAC。返回 false，提示残留仍在；`strong` 与备份还在，`strong-result.json` 已不在。退出码 1 的桩同样先删掉结果文件，`strong` 保留，返回 false。
   - 文件被占用时的对照：退出码 0 后删不掉 `strong`，返回 false，并提示仍有残留。这条复核本身成立，不抵消失败前删除结果文件。

3. **scripts/keep-awake.ps1:211、231 — 备份值和结果路径未按可执行文本转义。** scheme 和 ac/dc 直接拼进脚本；结果路径放进单引号且不转义 `'`。**依据：审查指定的生成脚本语法/引号，以及备份损坏边界；PRD §3.5 要求按备份值恢复，损坏时的行为必须合理。**
   - 合法 JSON 的 scheme 含分号时，生成行为 `powercfg /setactive <guid>; Set-Content -LiteralPath '<TEMP>\injected.txt' pwned 2>&1 | Out-Null`。在 TEMP 用函数挡住 `powercfg` 后执行该文本，标记文件被创建。这是提权脚本会执行的语句，不是父进程另写的命令。
   - 路径含 `'` 时，生成的 `Set-Content -Path '...O'Brien\...'` 不能通过解析。只含该错误行的 `pwsh -File` 退出码 1，脚本体不会运行。当前用户路径含空格和括号、不含撇号，正常备份生成的脚本可以解析，并含四个别名对应的 GUID、scheme 和两个 `Unregister-ScheduledTask`。

对照核验（未单独构成阻断）：
- 无残留时原函数返回 true，`Start-Process` 桩没有被调用，因此没有 UAC。
- 检测到的文件名是 `strong`、`strong-cmd`、`strong-result.json`、`power-backup.json`；任务名是 `keep-awake-strong`、`keep-awake-bootcheck`。未知设置键 `UNKNOWN` 不进入生成脚本。
- 四个恢复 GUID 与已删除的 `scripts/strong-op.ps1` 映射一致。本机 `powercfg /qh` 的 `UNATTENDSLEEP` 别名是 `7bc4a2f9-d8fc-4469-b07b-33eb785aaca0`，代码用的是旧工具同一处的 `7bc4f55f-8a8f-4ac3-8441-6c5b2f4a2c5a`。这是旧备份的写入目标，不另报为新 GUID 缺陷。
- 未发现测试文件，没有测试造假证据。

验证方式：AST 提取原文，路径全部在 TEMP。`Start-Process` 用桩记录 `-Verb RunAs` 并模拟取消、退出码 1、退出码 0，没有弹 UAC。生成脚本只在定义了 `powercfg` / `Unregister-ScheduledTask` 函数的会话里执行，没有调用真实 `powercfg` 改计划，也没有注销真实任务。审查前后 `%USERPROFILE%\.keep-awake` 仍只有 `awake-watcher.log`（1776 字节，2026-10-15 06:37:34.341）。`keep-awake.ps1` SHA-256 仍为 `4F5DA736E489A25E4AEB2C0AA0B1F8455335D97D486DA5B091F16049501F2FEF`。

## 第 2 遍

BLOCKING — 问题 1 的有恢复行路径和问题 3 的拒绝生成已成立；问题 2 的成功路径不删除 strong-result.json.stale，仍返回 true 并报已清理。无备份分支把字面量反引号加 $false 写进提权脚本，结果文件写不出来。

审查时间：2026-10-15 23:29:26。重新读取当前 `Invoke-LegacyCleanup`（180–299）。本轮文件 SHA-256 为 `8003C844EF39224DA493E8F55761A9891C7AA8D60124DF07073B067BA456D8B9`，与上一轮不同。没有修改代码，没有弹 UAC，没有改电源计划。

### 问题 1：有恢复行时成立

`224–228`、`250–252`、`266–275` 在有恢复行时把 `$LASTEXITCODE` 写进 `$script:restoreFailed`，结果字段在提权脚本里计算，失败则 `exit 1`。父函数退出码非 0 或 `restored=false` 都返回 false，不报成功。

隔离复现：生成文本含 `$LASTEXITCODE` 和 `exit 1`。用函数挡住 `powercfg` 后 `pwsh -File` 退出码 1，结果文件为 `{"restored":false}`。父函数收到退出码 1 时返回 false，保留 `strong` 与备份，提示可能未被恢复。退出码 0 但 `restored=false` 时返回 false，提示「自报恢复未成功」，不报已恢复。

### 问题 2：取消路径成立，成功路径未清 stale

`257–260`、`291`：UAC 取消把 `.stale` 移回，旧内容 `{"old":1}` 还在，`strong` 与备份保留，返回 false。退出码 1 时删除 `.stale`，新结果文件 `{"restored":false}` 留下，返回 false。

**残留阻断：`280–284` 成功时只删 strong/cmd/result/backup，不删 `$staleResult`。** 隔离复现：预置旧结果文件，桩返回退出码 0 且 `restored=true`。函数返回 true，输出「已清理」，四个原残留文件不在，但目录里仍有 `strong-result.json.stale`。这不符合本轮给出的「成功路径清理 stale」。

### 问题 3：拒绝生成成立；无备份的结果字面量仍带反引号

损坏 JSON、scheme 含分号、`ac=null` 都在调用 `Start-Process` 之前返回 false，残留文件保持原样，没有生成提权脚本。含 `'` 的路径写成 `O''Brien`，生成文本可以解析。

**直接影响：250 行 else 用单引号包住反引号加 $false，反引号不会被吃掉。** 无备份时生成文本的 restored 右值仍是字面量反引号加 $false，不是布尔 $false。该脚本解析通过，`pwsh -File` 退出码 0，但结果文件没有被写成 restored:false。有恢复行的双引号分支不受这一条影响。

## 第 3 遍

PASS — 两处残留都已消除：成功路径会删掉 strong-result.json.stale；无备份生成文本是 restored = $false，执行后 JSON 为 {"restored":false}。

审查时间：2026-10-15 23:36:00。重新读取当前 `Invoke-LegacyCleanup`。本轮 SHA-256 为 `E1AF6FD7545571E96BA6F400F1E7ADFEDA1F0224602AB4DD79C8C648128842C9`，与第 2 遍不同。没有修改代码，没有弹 UAC，没有改电源计划。

1. **stale 清理成立。** `280` 行 `Remove-Item` 现在包含 `$staleResult`。隔离复现：预置 strong、strong-cmd、power-backup.json 和旧 strong-result.json，桩返回退出码 0 且 restored=true。原函数返回 true，输出已清理，目录条目为空，没有留下 `.stale`。
2. **无备份字面量成立。** `250` 行 else 已是双引号 `` "`$false" ``。生成文本末行是 `@{ restored = $false; at = '2026-10-15 23:36:00' }`，解析错误数为 0。用函数挡住 `Unregister-ScheduledTask` 后 `pwsh -File` 退出码 0，结果文件为 `{"restored":false,"at":"2026-10-15 23:36:00"}`。
