# Codex Safe Install

Use this path for local Codex testing from this fork. It avoids `.mcpb`, dynamic release downloads, and upstream self-update.

## Install From `main`

Run from a local Terminal session on macOS:

```bash
cd <repo>
git switch main
git pull --ff-only origin main
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
make release
mkdir -p ~/bin
rm -f ~/bin/CheICalMCP
cp .build/release/CheICalMCP ~/bin/CheICalMCP
chmod +x ~/bin/CheICalMCP
codesign --force --sign - ~/bin/CheICalMCP
~/bin/CheICalMCP --setup
codex mcp add che-ical-mcp -- ~/bin/CheICalMCP
codex mcp get che-ical-mcp
```

If TCC dialogs do not appear, run this from Terminal, not SSH:

```bash
tccutil reset Calendar com.checheng.CheICalMCP
tccutil reset Reminders com.checheng.CheICalMCP
~/bin/CheICalMCP --setup
```

## Runtime Safety Defaults

The hardened branch defaults to `CHE_ICAL_MCP_PROFILE=read` when the variable is absent. That exposes only Calendar/Reminders read/search tools and denies direct mutation calls before handler dispatch.

Use mutation profiles only for controlled local testing:

```bash
CHE_ICAL_MCP_PROFILE=write_safe ~/bin/CheICalMCP
CHE_ICAL_MCP_PROFILE=destructive ~/bin/CheICalMCP
```

Optional runtime constraints can further reduce blast radius:

```bash
CHE_ICAL_MCP_ALLOWED_CALENDARS="Work,Personal"
CHE_ICAL_MCP_MAX_DATE_RANGE_DAYS=30
CHE_ICAL_MCP_MAX_RESULT_COUNT=100
CHE_ICAL_MCP_CONFIRMATION_TOKEN="$(openssl rand -hex 16)"
CHE_ICAL_MCP_AUDIT_LOG="$HOME/Library/Application Support/CheICalMCP/audit.log"
```

Notes:

- `CHE_ICAL_MCP_ALLOWED_CALENDARS` applies only to scope fields that the selected tool handler actually uses. When configured, scoped calls must include the tool-specific calendar or list argument; unscoped calls are denied. Tools without a pre-dispatch scope, ignored/spoofed scope fields, and ID-selected mutation calls are denied under this allowlist. Batch create calls must scope every item with an allowed `calendar_name`. If this variable is present but empty or whitespace-only, the server fails closed.
- `CHE_ICAL_MCP_MAX_RESULT_COUNT` requires supported read calls to pass an explicit `limit` at or below the cap. For `cleanup_completed_reminders` binding mode, the cap applies to the number of supplied `reminder_ids` because `limit` is ignored in that mode.
- `CHE_ICAL_MCP_MAX_DATE_RANGE_DAYS` denies read/query date ranges above the cap. It applies to range-based read tools such as `list_events`, `search_events`, `list_events_quick`, `check_conflicts`, and `find_duplicate_events`; it does not cap event durations for create/update mutations. `search_events` must include explicit `start_date` and `end_date`; `list_events_quick` ranges are allowed only when their known duration is within the cap.
- `CHE_ICAL_MCP_CONFIRMATION_TOKEN` requires write-safe and destructive tool calls to include a matching `confirmation_token` argument. When configured, mutation tool schemas expose `confirmation_token` so schema-driven MCP clients can send it. Use a per-session token and keep Codex tool approval enabled. If this variable is present but empty or whitespace-only, the server fails closed.
- Invalid numeric runtime caps fail closed: the server denies tool calls instead of silently ignoring the bad setting.

## Reminder History Live Check

Use a disposable reminder list before relying on historical completion dates:

1. Create a temporary list in Reminders.app, for example `CheICalMCP Disposable Test`.
2. Call `create_reminder` with that `calendar_name` and `completion_date: "2026-05-10T12:00:00+02:00"`.
3. Call `list_reminders` with the same `calendar_name`, `filter: "completed"`, `include_diagnostics: true`, and a small `limit`.
4. Verify the returned reminder is completed and the returned `completion_date` represents the same instant.
5. Create another reminder in the disposable list, then call `complete_reminder` with `completed: true` and the same `completion_date`.
6. Read it back with `list_reminders(include_diagnostics: true)` and verify the same instant is returned.
7. Delete the disposable list after the check.

`--self-update` is disabled unless the process explicitly sets:

```bash
CHE_ICAL_MCP_ENABLE_SELF_UPDATE=1 ~/bin/CheICalMCP --self-update
```

For Codex, keep `approval_mode = "approve"` on mutation tools in `~/.codex/config.toml` until the hardened branch is installed and verified.
