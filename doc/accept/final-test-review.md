PASS

2026-10-16 01:06 独立运行 `tests/run-tests.ps1`，退出码 0。四组合计 150 条断言均通过：install 13、watcher 48、CLI 63、statusline 26。真实 `%USERPROFILE%\.keep-awake` 前后仍只有 `awake-watcher.log`（1776 字节，2026-10-15 06:37:34.341）。未调用真实防睡眠 API、未弹 UAC、未创建计划任务。

夹具没有把被测控制流换成假成功。watcher 只 AST 替换 `Get-PowerLine`，互斥量改成独立 Local 名，预加载同名 Native 桩，并用模拟时钟推进真实状态机；断言核对发布序列、持有次数、无 DISPLAY 位、finally 清标志删 pid。CLI 只替换电源与 `Start-Watcher`，`Stop-Process` 被调用即失败，提权桩只记录并抛取消；退出码用脚本末尾 completion marker 区分提前 `exit`，失败用例不会因子进程收尾成功而通过。statusline 源文件原样复制，只模拟 CIM；stdin 写入后故意不关闭，10 秒内必须退出且恰好一行。卸载使用真实 `uninstall.ps1`。`schtasks.ps1` 桩会被 pwsh 实际调用，不是空过。

这 12 条有界用例均有对应断言，不表示穷尽组合。

| 计划 | 覆盖 |
|---|---|
| 1 电源四态转换 | watcher：unplug-replug、unknown-recover、initial-unknown、battery |
| 2 首次 API 失败 | initial-api-failure |
| 3 重申失败后拔电 | reassert-failure、uncertain-retry、uncertain-still-failing |
| 4 释放 API 失败 | release-failure-retry |
| 5 发布失败重试 | publish-failure-retry、released-publish-retry |
| 6 CLI 空文件 | status-empty、on-empty-state、off-empty |
| 7 复用 PID | status-foreign、on-foreign、off-foreign |
| 8 错误命令且不建 settings | unknown-command；各 CLI 用例检查不创建 settings |
| 9 损坏备份 | legacy-bad-json；卸载侧 real-off-corrupt-backup |
| 10 注入被拒 | legacy-bad-scheme、legacy-bad-ac；输出不得含 PWNED，且未提权 |
| 11 取消 UAC | legacy-cancel-uac：证据还原，未报已清理 |
| 12 statusline | 13 场景均单行；外来 pid 为 stale；空/缺状态为 ⚠；stdin 不关闭 |

未自动认证，不能当成已通过：物理插拔电、真实 `SetThreadExecutionState`、真实 UAC 对话框、重启后不自启、两个真实进程争用 `Global\keep-awake-watcher`、真实 `schtasks` 与真实电源计划。

## 真正零字节夹具复核

PASS 保持。01:06 那次 150 通过里，CLI 与 statusline 的空字符串是 `Set-Content -Encoding utf8BOM -NoNewline`，文件是 3 字节 BOM，不是零字节。那次不能算测过严格零字节。

当前两处已改为空值走 `[IO.File]::WriteAllBytes($path, [byte[]]@())`，非空仍用原来的 `Set-Content`。`test-cli.ps1:117`、`test-statusline.ps1:62`。产品代码未改。

2026-10-16 01:15:05 只独立重跑这两组，未重跑 install/watcher：`test-cli.ps1` 63 条、退出码 0；`test-statusline.ps1` 26 条、退出码 0。空文件用例为 CLI 的 status-empty、off-empty、on-empty-state，以及 statusline 的 empty-mode、empty-pid、empty-state。真实状态目录未变。
