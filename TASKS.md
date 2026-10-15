# 任务清单（来源：doc/PRD.md，2026-10-14 契约重定）

> 进度真相。实现已完成（2026-10-14），逐条对抗审查后勾选。同一条目最多 review 3 遍。
> review 入口：初期 codex exec --yolo 默认模型 gpt-6.1-sol（用户裁决：不追求账号不支持的档位）；后续按用户明确指示改用 Herdr `pi-9` 标签页。后续报告以实际入口为准，不将 pi-9 的审查误标为 Codex。

- [x] 1. `on` 命令（PRD §3.1）——插电 exit 0 且守护进程 holding-ac；电池启动但明确提示未挡；电源 Unknown exit 1 不启动；重复 on 幂等（review 第 3 遍 + 快速回归通过）
- [x] 2. 守护进程 `awake-watcher.ps1`（PRD §3.2）——不设 ES_DISPLAY_REQUIRED；60s 重申/5s 轮询；拔电释放插回续挡；unknown/API 失败释放并标记；单实例；stop 哨兵 5s 内退出并清标志删 pid（review 第 3 遍通过，三态 FlagState 修复后）
- [x] 3. `off` 命令（PRD §3.3）——停守护进程；删 mode/info/watcher-state；不动电源计划；不创建 settings 文件；无残留时无 UAC（review 第 2 遍通过：强杀验证+归属校验+删除复核+哨兵先行）
- [x] 4. `status` 命令（PRD §3.4)——四态如实显示 + 电源行 + 屏幕策略说明 + 旧残留警告（review 第 2 遍通过：空文件 null 防护）
- [x] 5. 旧版残留清理（PRD §3.5）——检测任务/备份/strong 文件；有残留才提权恢复+删除+复核；失败保留残留如实报告（review 第 3 遍通过：备份严格校验防注入 + 真实 restored + stale 证据链）
- [x] 6. 旧钩子移除（PRD §3.6）——settings 不存在不创建；只删 keep-awake arm/disarm 条目；其余钩子保留（review 第 2 遍通过：词边界匹配防 arm/disarm 互误删）
- [x] 7. `statusline.ps1`（PRD §3.7）——只读文件输出单行四态；不读 stdin（review 第 2 遍通过：pid 归属校验 + 空文件每行保证）
- [x] 8. `install.ps1` / `uninstall.ps1`（PRD §3.8）——install 仅语法检查+残留检测；uninstall 跑 off+核验+删状态目录，任务删不掉 exit 1（pi-9 第 3 遍通过：含真实 off 清理失败传播，13 条回归断言通过）
- [x] 9. 文档一致性（PRD §3.9）——SKILL/README×2/QUICKSTART 与代码行为一致，无旧契约宣传（pi-9 第 2 遍通过：入口与元数据限定正常运行/旧恢复例外，不承诺任务永不中断）

## 收尾验收（非新增功能）

- [x] 有界对抗测试与独立复核——四组 150 个断言通过；真正零字节夹具纠正后受影响 89 个断言由 pi-9 再独立复跑通过；语法/BOM/JSON/本地链接通过。证据：`doc/accept/final-test-review.md`。
- [x] 交付材料——`tests/README.md`、`doc/accept/SUMMARY.md`、`doc/accept/session-log.md`、`doc/accept/USER-ACCEPTANCE.md`。
- [ ] 用户本人真机走查并签字——按 `doc/accept/USER-ACCEPTANCE.md` 执行。物理插拔电/真实 API/UAC/重启/互斥量竞争等未由模拟测试认证；不得由 Agent 代签。

当前状态：**待用户验收**（2026-10-16 01:17:46）。所有改动未提交 Git。
