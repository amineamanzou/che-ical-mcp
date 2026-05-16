## Why

2026-05-16 的 Reminders 清理留下了一批一次性 EventKit Swift 腳本。它們證明了幾個可重用需求：安全讀取 completed reminders、診斷 reminder date/recurrence 欄位，以及在需要重建歷史時設定 completion date。

現在 MCP fork 已有 read-only default、policy gate、allowlist、confirmation token、audit logging 和 self-update gate，可以把低風險且可重用的部分轉成受政策保護的一級 MCP 能力，而不是繼續依賴 vault 裡的臨時腳本。

## What Changes

- 在 reminder read output 加入 opt-in diagnostics 模式，回傳 bounded due date components、completion date 和 recurrence summary。
- 擴充 `create_reminder`，允許建立已完成 reminder 並設定明確 `completion_date`。
- 擴充 `complete_reminder`，允許在 `completed=true` 時指定明確 `completion_date`。
- 保持現有 safety model：預設 read-only、mutation 仍屬 write-safe、configured confirmation token 仍必須通過、EventKit-derived read output 仍需 untrusted wrapping。

## Non-Goals

- 不實作 reminder list migration、clone/move/delete workflow。
- 不新增 destructive list deletion 工具。
- 不複製 vault Swift 腳本進 production source、package target 或 supported CLI。
- 不新增 dedicated historical-completion tool；優先擴充既有 reminder tools。
- 不改變 default `read` profile 暴露面。

## Capabilities

### New Capabilities

- `reminder-history-diagnostics`: Completed-reminder reads, reminder date/recurrence diagnostics, and historical completion-date support for maintained MCP reminder tools.

### Modified Capabilities

(none)

## Impact

- Affected specs: `reminder-history-diagnostics`
- Affected code: `Sources/CheICalMCP/Server.swift`, `Sources/CheICalMCP/EventKit/EventKitManager.swift`, `Sources/CheICalMCP/ToolPolicy.swift`, `Sources/CheICalMCP/Validation.swift`
- Affected tests: reminder handler tests, policy profile tests, schema/dispatch parity tests
- Affected docs: README tool reference and safe install/runtime notes if new arguments affect operator usage
