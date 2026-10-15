BLOCKING

审查对象：`scripts/keep-awake.ps1` 的 `Remove-LegacyHooks`（301–332）。依据 `doc/PRD.md` §3.6 与 `TASKS.md` 条目 6。审查时间：2026-10-15 23:36:00。只报告需求、实现及指定边界的阻断项。没有修改代码，没有读写真实 `settings.json`。

1. **scripts/keep-awake.ps1:314–316 — UserPromptSubmit 用 `*arm*` 匹配，会删掉 command 含 `disarm` 的条目。** `disarm` 含有子串 `arm`。Stop 用 `*disarm*`，不会误配单独的 `arm`。因此同一条 `keep-awake.ps1 disarm` 放在 UserPromptSubmit 会被删，放在 Stop 才会按标记删除。**依据：PRD §3.6“只删除 command 含 keep-awake.ps1 + arm/disarm 标记（UserPromptSubmit→arm，Stop→disarm）；其余钩子原样保留”。**
   - 隔离复现：TEMP 里的 settings 含 `other.ps1`、`keep-awake.ps1 arm`、`keep-awake.ps1 disarm`（UserPromptSubmit），以及 `keep-awake.ps1 arm`、`keep-awake.ps1 disarm`、`notify.ps1`（Stop）。原函数写回后，UserPromptSubmit 只剩 `other.ps1`，`disarm` 那条没了。Stop 仍保留 `keep-awake.ps1 arm` 和 `notify.ps1`，只删了 `disarm`。`theme` 仍在。

对照核验（未单独构成阻断）：
- 两个 settings 都不存在时不创建目录或文件。真实 `%USERPROFILE%\.pi\agent\settings.json` 与 `.claude\settings.json` 的长度和修改时间在审查前后不变。
- 不含 `keep-awake.ps1` 的钩子，即使 command 含 `arm`/`disarm`，文件字节内容不改写。
- 非法 JSON `{not json` 原样保留，并输出转换失败。零字节文件上 `ConvertFrom-Json` 不抛错，函数把它当成没有 hooks 跳过，文件仍是空的、没有被覆盖。
- 缺 `command` 的条目保留；本工具 arm 条目被删。只含本工具条目时，`env` 保留，对应事件属性被去掉，留下 `"hooks": {}`。
- 删除后只剩一个他人钩子时，仍写成数组，没有收成单个对象。输入本身是单个对象的 `Stop` + `keep-awake.ps1 disarm` 能删掉该事件。
- 未发现测试文件，没有测试造假证据。

验证方式：AST 提取 `Remove-LegacyHooks` 原文，在子进程把 `USERPROFILE` 指到 TEMP 后执行。没有读取真实 settings 内容。`keep-awake.ps1` SHA-256 为 `E1AF6FD7545571E96BA6F400F1E7ADFEDA1F0224602AB4DD79C8C648128842C9`。

## 第 2 遍

PASS — `*arm*` 已改为词边界；原反例里 UserPromptSubmit 只删 arm，Stop 只删 disarm。

审查时间：2026-10-15 23:45:39。重新读取当前 `Remove-LegacyHooks`。本轮 SHA-256 为 `E0699A22DA6FE1314A258204F01D771BCE85B69C12D2713A585D32E5A5EC6692`，与上一轮不同。没有修改代码，没有读写真实 settings。

`320` 行匹配已是 `-match "\b$marker\b"`。隔离复现使用上一轮同一份混合钩子：UserPromptSubmit 含 `other.ps1`、`keep-awake.ps1 arm`、`keep-awake.ps1 disarm`；Stop 含 `keep-awake.ps1 arm`、`keep-awake.ps1 disarm`、`notify.ps1`。原函数写回后，UserPromptSubmit 保留 `other.ps1` 和 `keep-awake.ps1 disarm`，只删了 arm。Stop 保留 `keep-awake.ps1 arm` 和 `notify.ps1`，只删了 disarm。`theme` 仍在。
