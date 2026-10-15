# 隔离回归测试

要求 Windows + PowerShell 7（`pwsh`）。在仓库根目录运行：

```powershell
pwsh -NoProfile -File .\tests\run-tests.ps1
```

任何断言失败、语法错误、非 UTF-8 BOM 脚本、失效本地链接或 JSON 示例错误，入口返回非零。四组按顺序运行，不并发。

| 测试文件 | 场景与断言 |
|---|---|
| `test-install-uninstall.ps1` | 安装检查、失败不删备份、残留任务、独占文件、真实 off 损坏备份、重复卸载；13 断言 |
| `test-watcher.ps1` | 12 个电源/API/状态发布序列，真实控制流；48 断言 |
| `test-cli.ps1` | 16 个 CLI/清理/旧钩子场景；63 断言 |
| `test-statusline.ps1` | 13 种状态，单行/不读 stdin/文件不变；26 断言 |

合计 **150 个断言**，不是 150 个独立场景，也不是穷尽所有组合。对抗用例映射及独立复核见 `../doc/accept/final-test-review.md`。

## 隔离方式与覆盖边界

- 每组在随机 TEMP 目录构造用户及脚本副本，在新 pwsh 子进程设定独立 `USERPROFILE`。完成后 finally 删除临时文件。
- 不读取秘密、不操作真实 `.keep-awake`、不创建真实计划任务、不触发 UAC、不修改电源计划、不结束真实进程。
- watcher 以 AST 替换电源读取函数，以同名假 Native 类注入 API 结果；使用独立互斥量名称和虚拟时钟。状态机、发布、重试和 finally 仍是产品代码。
- CLI 以 AST 替换电源/启动 watcher 的系统边界。CIM、进程、提权、等待通过函数桩模拟。用脚本末尾完成标记区分提前 exit；不是直接调用真实启动路径的端到端测试。
- statusline 复制原脚本，仅模拟 CIM；stdin 管道故意保持打开。快照只比较 `.keep-awake`、`.pi`、`.claude`，不把 PowerShell 宿主自身的启动缓存算成组件写入。
- “空文件”夹具通过 `WriteAllBytes` 产生真正 0 字节，而非只写 UTF-8 BOM。
- 安装/卸载测试通过 PATH 的 PowerShell `schtasks` 桩模拟任务查询。其中损坏备份用例运行真实 CLI，不触发提权。

**未认证的真机行为：** 物理插拔电、实际空闲睡眠/显示超时、真实 API 返回值、UAC 对话框与真实旧计划恢复、重启注销、跨进程 Global mutex 竞争，以及实际 watcher 启动路径兼容性。请按 `../doc/accept/USER-ACCEPTANCE.md` 人工走查，测试不会替用户签字。
