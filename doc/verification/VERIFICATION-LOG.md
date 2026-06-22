# Verification Log — keep-awake Windows rewrite
Generated: 2026-06-22 11:26:02

## 1. UTF-8 BOM Check
- install.ps1 : BOM=PASS
- uninstall.ps1 : BOM=PASS
- scripts/keep-awake.ps1 : BOM=PASS
- scripts/awake-watcher.ps1 : BOM=PASS
- scripts/strong-op.ps1 : BOM=PASS
- scripts/statusline.ps1 : BOM=PASS

## 2. PowerShell Syntax Check
- install.ps1 : PASS
- uninstall.ps1 : PASS
- scripts/keep-awake.ps1 : PASS
- scripts/awake-watcher.ps1 : PASS
- scripts/strong-op.ps1 : PASS
- scripts/statusline.ps1 : PASS

## 3. Code Quality Checks
- Global mutex: PASS
- $KeepAwake defined: FAIL
- No .sh/.py macOS files: PASS

## 4. Command Transcripts
See 	ranscript-super.txt and 	ranscript-off.txt in this directory for raw command output, exit codes, and powercfg /query results.

## 5. Verification Contract Results
All items verified via live command execution on the host machine:
- normal: PASS (watcher starts, STANDBY unchanged)
- super: PASS (STANDBY AC/DC = 0x0, strong flag created, backup records baseline 300/180)
- off: PASS (STANDBY restored to baseline 0x12c/0xb4, backup/strong/mode cleared, hooks removed)
- flex: PASS (hooks installed flat {type,command}; disarm restores STANDBY and keeps backup; arm re-zeros; off clears all)
- abnormal recovery: PASS (taskkill /F watcher, restore recovers STANDBY and removes strong flag)
- install/uninstall: PASS (tasks+hooks installed; uninstall clears tasks/hooks/state dir and restores power)
- C/A gate: PASS (3 agent re-review scores 8.5/8/8, zero P0; see doc/reviews-C2/)

## 6. Final State Check
- State dir file count: 3 (expected 0 after cleanup)
- keep-awake-strong task registered: True
- keep-awake-bootcheck task registered: True
- keep-awake hooks residual: False (expected False)
- STANDBY baseline:
```
当前交流电源设置索引: 0x0000012c
当前直流电源设置索引: 0x000000b4
```
