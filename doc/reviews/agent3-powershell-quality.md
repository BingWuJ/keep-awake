# Agent 3 · PowerShell 代码质量 Code Review（第 3 轮，基于最新代码）

> 审查时间：2026-06-22
> 审查基准代码：6 个 `.ps1` 文件（`scripts/*.ps1` + `install.ps1` + `uninstall.ps1`）+ 实测 BOM 状态
> 审查方式：以「PowerShell 惯用法/错误处理/跨版本兼容/可维护性」单一视角独立通读。

**评分：7 / 10**

总体评价：代码骨架规范——`[CmdletBinding()]`、`[ValidateSet()]`、`$ErrorActionPreference='Stop'`、参数校验、`Get-Command pwsh.exe` fallback 到 `powershell.exe` 的跨版本兼容写法都已就位，`awake-watcher.ps1` 的 Mutex/try-finally 与 `strong-op.ps1` 的指令文件驱动设计体现了对 Windows 习惯的掌握。相比第 2 轮，hook 命令已优先用 pwsh（`Get-HookShell`）、`Install-Task` 改用 `ScheduledTasks` 模块、statusline 加了换行。但存在 **1 条 P0**：所有 `.ps1` 文件**均无 UTF-8 BOM**（实测 6 文件首三字节均为 `23 21 2F` = `#!/`），直接违反目标「关键技术约束/Agent 3 视角」明确要求的「编码 UTF-8 BOM」，在 fallback 到 Windows PowerShell 5.1 时会导致中文字符串乱码甚至破坏引号配对引发语法错误。另有 2 条 P1（Start-Watcher 不验证启动、powercfg 错误静默）。

---

## 实测证据：BOM 缺失

```
keep-awake.ps1      BOM=False first3=[23 21 2F]
awake-watcher.ps1   BOM=False first3=[23 21 2F]
strong-op.ps1       BOM=False first3=[23 21 2F]
statusline.ps1      BOM=False first3=[23 21 2F]
install.ps1         BOM=False first3=[23 21 2F]
uninstall.ps1       BOM=False first3=[23 21 2F]
```

（`23 21 2F` = `#!/`，即 shebang 起始，无 `EF BB BF` BOM）

---

## 未修复 Issue 列表

### P0 · 所有 `.ps1` 文件缺少 UTF-8 BOM

- **文件:行号**：`scripts/keep-awake.ps1`、`scripts/awake-watcher.ps1`、`scripts/strong-op.ps1`、`scripts/statusline.ps1`、`install.ps1`、`uninstall.ps1`（文件级）
- **问题**：目标明确要求「编码 UTF-8 BOM」。当前 6 个文件全部无 BOM。脚本内含大量中文字符串（`Write-Host "🔆 NORMAL..."`、错误提示、日志）。`Get-Command pwsh.exe` 不存在时会 fallback 到 `powershell.exe`（PS 5.1）；PS 5.1 在中文系统下按 GBK（CP936）解析无 BOM 的 UTF-8 字节，轻则中文乱码，重则奇数字节破坏字符串引号配对导致解析失败。
- **影响**：pwsh（PS7）用户不受影响（PS7 默认 UTF-8 无 BOM）；仅 PS 5.1 fallback 用户受影响。但因目标硬性要求 BOM，且 fallback 路径确实存在，定为 P0。
- **修复建议**：用 PowerShell 一次性给 6 个文件加 UTF-8 BOM：

  ```powershell
  Get-ChildItem -Recurse -Include *.ps1 | ForEach-Object {
      $c = Get-Content $_.FullName -Raw -Encoding UTF8
      [System.IO.File]::WriteAllText($_.FullName, $c, (New-Object System.Text.UTF8Encoding($true)))
  }
  ```

  注意：加 BOM 后 shebang `#!/usr/bin/env pwsh` 在 Unix 风格调用下可能受影响，但本工具 Windows-only，无影响。

### P1 · `Start-Watcher` 不验证子进程是否真正启动

- **文件:行号**：`scripts/keep-awake.ps1:85-94`
- **当前代码**：

  ```powershell
  Start-Process -FilePath $exe `
      -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$Watcher `
      -WindowStyle Hidden -PassThru | Out-Null
  ```

- **问题**：`Start-Process` 后立即返回，不检查 watcher 日志/PID 文件/进程存在。若 `awake-watcher.ps1` 因执行策略、Add-Type 编译失败、Mutex 异常等原因未起来，用户要到 `status` 才发现没守护，期间误以为已防护。
- **修复建议**：启动后等待最多 3s 轮询 `Test-WatcherRunning`；失败时读 `awake-watcher.log` 末几行并返回 `$false`/抛出，让 `Invoke-On` 诚实告知「守护进程启动失败」而非宣称已开。

### P1 · `Set-SettingValue` 与 `/setactive` 不检查 `$LASTEXITCODE`

- **文件:行号**：`scripts/strong-op.ps1:113-122`、`168`、`209`、`231`
- **问题**：`[void](powercfg ...)` 丢弃退出码，失败静默（与 Agent 1 视角同一条，从代码质量角度复指）。
- **修复建议**：封装一个 `Invoke-Powercfg` helper 统一捕获 stdout/stderr + `$LASTEXITCODE`，非零时写日志并返回失败标记。

### P2 · `Get-SettingValue` 二进制回退解析脆弱

- **文件:行号**：`scripts/strong-op.ps1:103-110`
- **问题**：语言正则失败后取「最后两个 8 位十六进制值」作 AC/DC。若微软调整 `powercfg /query` 输出顺序或存在额外十六进制字段，会解析错误。
- **修复建议**：保留兜底但加 WARN 日志「使用二进制回退解析，结果可能不准」；或改用 `powercfg /query` 的英文 locale 强制输出（但 `/query` 无 locale 参数，可考虑 WMI `Win32_PowerPlan` 替代）。

### P2 · `$mode` 与 `$Mode` 混用

- **文件:行号**：`scripts/keep-awake.ps1:176`（`"@{ mode = $mode; started = ... }"`，参数名为 `$Mode`）
- **问题**：PowerShell 不区分大小写故能跑，但降低可读性。
- **修复建议**：统一 `$Mode`。

### P2 · `InfoFile` 写的是 here-string 字符串而非结构化 JSON

- **文件:行号**：`scripts/keep-awake.ps1:176`
- **问题**：`"@{ mode = $mode; started = $(Get-Now) }"` 写入的是 PowerShell hashtable 字面量文本，无法被 `ConvertFrom-Json` 解析；后续若想程序化读取需额外处理。
- **修复建议**：`@{ mode = $Mode; started = (Get-Now) } | ConvertTo-Json`。

### P2 · `Install-Task` 临时脚本把路径嵌入单引号字符串

- **文件:行号**：`scripts/keep-awake.ps1:Install-Task`（`$strongArg = '-NonInteractive -ExecutionPolicy Bypass -File "' + $StrongOp + '"'`、`$bootArg` 同理，L420-421）
- **问题**：`$StrongOp`/`$KeepAwake` 路径若含单引号会断脚本。Windows 路径含单引号极罕见（用户名通常不含），但非零风险。
- **修复建议**：用 `ConvertTo-Json` 序列化参数后注入，或改用 `Start-Process -Verb RunAs` 直接内联执行 `Register-ScheduledTask`。

### P2 · `Install-Hook` / `Uninstall-Hook` 直接 mutate `ConvertFrom-Json` 结果

- **文件:行号**：`scripts/keep-awake.ps1:Install-Hook` / `Uninstall-Hook`
- **问题**：对 PSCustomObject 用 `Add-Member -Force` + 数组替换，复杂嵌套 settings.json 下易意外改引用；`ConvertTo-Json -Depth 10` 重写格式可能与原文件不一致。
- **修复建议**：深拷贝后修改，或安装前备份原 `settings.json`。

### P2 · 多处硬编码超时未参数化

- **文件:行号**：`keep-awake.ps1` 多处（Stop-Watcher 8s、Invoke-StrongOp 20s、轮询 300/500ms）
- **修复建议**：顶部定义 `$StopTimeoutSec`、`$StrongOpTimeoutSec`、`$PollIntervalMs` 常量。

### P2 · `statusline.ps1` BOM 剥离仅针对 UTF-8

- **文件:行号**：`scripts/statusline.ps1:15`（`$raw -replace '^\xEF\xBB\xBF', ''`）
- **问题**：只剥 UTF-8 BOM，UTF-16 LE BOM 会残留。
- **修复建议**：用 `[System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Convert(...))` 更稳健，或 `Get-Content -Encoding UTF8`。影响极小（pi/Claude Code statusLine 均送 UTF-8）。

### P2 · 缺少 PS 5.1 测试矩阵声明

- **问题**：多处 fallback 到 `powershell.exe`，但 `Add-Type`/JSON cmdlet/CIM 在 PS 5.1 vs PS7 行为差异未经验证。
- **修复建议**：README 明示「推荐 PS7；PS 5.1 核心命令行可用但计划任务需 pwsh」，或加 PS 5.1 冒烟测试。

### P2 · 日志无大小限制

- **文件:行号**：`awake-watcher.ps1:24`、`strong-op.ps1:35`
- **修复建议**：启动时日志 > 1MB 则轮转。

---

## 加分项

- `[CmdletBinding()]` + `[ValidateSet(...)]` + `$ErrorActionPreference='Stop'` 规范。
- `awake-watcher.ps1` 的 Mutex + AbandonedMutexException 恢复 + try/finally 显式清标志，符合 Windows 并发与资源释放习惯。
- `strong-op.ps1` 用指令文件（`strong-cmd`）驱动避免 schtasks 命令行引号问题，设计合理。
- `install.ps1` 启动时用 `[System.Management.Automation.Language.Parser]::ParseFile` 预检语法，提前暴露错误。
- `Get-HookShell` 优先 pwsh、fallback powershell，跨版本兼容到位。

---

## A 环节复验点

1. 6 个 `.ps1` 文件首三字节均为 `EF BB BF`（UTF-8 BOM），且 pwsh 下行为不变。
2. 在 PS 5.1（`powershell.exe -File`）下运行 `keep-awake.ps1 status`，中文输出无乱码。
3. 故意破坏 watcher 脚本语法后 `on normal`，确认 `Invoke-On` 报「守护进程启动失败」而非宣称已开。
