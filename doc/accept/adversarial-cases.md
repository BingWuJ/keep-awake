# 对抗用例（有界）

代表性失败边界，不是穷尽组合。不替代 `tests/test-install-uninstall.ps1` 已有 13 断言，也不替代用户实机签字。下列均可在 TEMP 用桩完成，**不必真机**；禁止真 UAC、真改电源计划、真插拔电。

| # | 输入 | 应有结果 | 必须真机 |
|---|---|---|---|
| 1 | 守护进程桩电源序列：Online → Offline → Online → Unknown；API 均成功 | 发布依次为 holding-ac、released-battery、holding-ac、error-power-unknown；Offline/Unknown 时模拟标志已释放；持有组合不含 ES_DISPLAY_REQUIRED | 否 |
| 2 | 首次 `SetThreadExecutionState` 返回 0 | 不发布 holding-ac；标记错误；不把未持有说成挡住 | 否 |
| 3 | 首次持有成功，60 秒重申返回 0，随后电源 Offline | 重申失败当轮不维持“已挡住”；若清除也失败，下一轮不得发布 released-battery | 否 |
| 4 | 已持有时拔电，清除 API 返回 0 | 不得发布 released-battery；保持错误/未确认释放，并继续重试清除 | 否 |
| 5 | 拔电后释放已成功，但写入 released-battery 第一次失败、之后成功 | 不得把文件留在旧的 holding-ac；失败后重试，最终文件为 released-battery | 否 |
| 6 | `mode`/`awake.pid`/`watcher-state` 为零字节，再跑 `on`、`status`、`off` | 不因 `.Trim()` 抛错退出；不把空状态显示成挡住；`off` 不结束无关进程 | 否 |
| 7 | pid 文件指向存活但命令行不含 `awake-watcher.ps1` 的进程；状态文件为 holding-ac | `on` 不把它当成已在运行的守护进程；`off` 不 `Stop-Process` 该 pid；`status` 不报挡住 | 否 |
| 8 | 未知命令；且 pi/Claude `settings.json` 不存在时跑 `on`/`off`/`status` | 未知命令 exit 1，不出现成功挡住句；不创建这两个 settings 文件或它们的目录 | 否 |
| 9 | 仅有损坏的 `power-backup.json`（如 `{broken`），跑真实 `off` | 拒绝生成提权脚本，exit 1，备份仍在；不弹 UAC。卸载侧传播已由 `real-off-corrupt-backup` 覆盖，不必另写 | 否 |
| 10 | 备份 scheme 含分号或不是 36 位十六进制 GUID；ac/dc 非纯整数 | 拒绝生成提权脚本，exit 1，残留仍在；不执行 scheme/ac 里的额外语句 | 否 |
| 11 | 有合法旧残留，提权启动被桩成用户取消 | exit 1；`strong-result.json` 从 `.stale` 移回，其他残留仍在；不报已清理 | 否 |
| 12 | `statusline.ps1`：stdin 写入无关文本；以及 mode=on + 外来 pid、零字节 state、缺失 state | 不读 stdin；每种输入恰好一行。外来 pid 为 stale 警告，不是 `● Awake (AC)`；空/缺失 state 为 `⚠`，不是裸 `● Awake` | 否 |
