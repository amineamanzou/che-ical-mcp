## Why

The 2026-05-16 Reminders cleanup produced a set of one-off EventKit Swift scripts. They exposed several reusable needs: safely reading completed reminders, diagnosing reminder date and recurrence fields, and setting a completion date when reconstructing history.

The MCP fork now has a read-only default, policy gate, allowlists, confirmation-token enforcement, audit logging, and self-update gating. The low-risk reusable behavior can therefore become first-class MCP capability protected by policy instead of continuing to depend on temporary scripts in the vault.

## What Changes

- Add an opt-in diagnostics mode to reminder read output, returning bounded due date components, completion date, and recurrence summary fields.
- Extend `create_reminder` so it can create a completed reminder with an explicit `completion_date`.
- Extend `complete_reminder` so callers can provide an explicit `completion_date` when `completed=true`.
- Preserve the existing safety model: default read-only profile, mutations remain write-safe, configured confirmation tokens still apply, and EventKit-derived read output remains wrapped as untrusted data.

## Non-Goals

- Do not implement reminder list migration, clone, move, or delete workflows.
- Do not add a destructive reminder-list deletion tool.
- Do not copy vault Swift scripts into production source, package targets, or supported CLI surfaces.
- Do not add a dedicated historical-completion tool; extend existing reminder tools instead.
- Do not change the default `read` profile exposure.

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
