## Summary

Harden the fork for local agent use by making the default MCP surface read-only, routing all tool calls through a central policy layer, and disabling the upstream self-update path unless explicitly enabled.

## Motivation

The current server exposes Calendar and Reminders reads, writes, deletes, batch operations, move/copy actions, undo/redo, and self-update in one default surface. That is too broad for a local agentic OS component where calendar/reminder contents are private and can contain prompt-injection payloads.

## Proposed Solution

- Introduce a capability profile with `read` as the default.
- Filter `ListTools` output so the default profile exposes only read/search tools.
- Enforce the same policy in `executeToolCall` so hidden mutations cannot be invoked by name.
- Expand untrusted-content wrapping to calendar/list/source names returned by `list_calendars`.
- Add a local audit-log skeleton for allow/deny policy decisions without logging EventKit titles, notes, or locations.
- Disable `--self-update` by default unless an explicit environment flag enables it.

## Non-Goals

- No Mail, Messages, Contacts, Notes, Photos, Maps, networked MCP, or remote MCP access.
- No signed/notarized release pipeline changes in this pass.
- No destructive profile enablement by default.
- No model-only confirmation mechanism.

## Impact

- Affected specs: `calendar-reminders-policy`
- Affected code: `Sources/CheICalMCP/Server.swift`, `Sources/CheICalMCP/Validation.swift`, `Sources/CheICalMCP/SelfUpdate.swift`, `Sources/CheICalMCP/main.swift`
