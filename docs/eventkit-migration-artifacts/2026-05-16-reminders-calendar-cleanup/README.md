# EventKit Migration Artifacts - 2026-05-16 Reminders/Calendar Cleanup

This directory records the migration inventory that motivated the next MCP
feature work. Source scripts are intentionally not copied here: they contain
private reminder titles, list names, and operational context. Keep the original
scripts in the private vault until a separate cleanup pass replaces them with
notes.

## Inventory Summary

- Source set: 20 local `EventKit*.swift` scripts reviewed on 2026-05-17.
- Total size: 2,427 lines.
- Archive mode: README-only, privacy-preserving inventory.
- Runtime status: none of these scripts are package sources, supported CLI
  tools, or MCP tools.

## Classification

The source filenames are not listed because several reveal private list names,
projects, or operational context. Artifact IDs below are stable within this
inventory only.

| Artifact | Lines | Status | MCP direction |
| --- | ---: | --- | --- |
| `artifact-01-access-probe` | 129 | diagnostic seed | Fold into a bounded EventKit access diagnostic if needed. |
| `artifact-02-reminder-title-read` | 45 | read seed | Superseded by scoped reminder listing; keep as evidence only. |
| `artifact-03-reminder-date-components` | 46 | read seed | Replace with reminder date diagnostics on `list_reminders`. |
| `artifact-04-completed-reminder-read` | 45 | read seed | Replace with bounded completed-reminder listing. |
| `artifact-05-recurrence-inspection` | 73 | read seed | Replace with recurrence diagnostics in reminder output. |
| `artifact-06-historical-completion-write` | 174 | write-safe seed | Replace with historical completion support on maintained tools. |
| `artifact-07-reminder-list-create` | 75 | write-safe seed | Covered by existing calendar/list creation patterns; revisit only with policy tests. |
| `artifact-08-explicit-subset-move` | 106 | risky workflow seed | Future workflow must use explicit IDs and dry-run/confirmation semantics. |
| `artifact-09-list-migration` | 143 | destructive workflow seed | Future workflow must split dry-run, move/clone, verification, and deletion. |
| `artifact-10-clone-before-delete` | 152 | destructive workflow seed | Future workflow must preserve completed history before deletion. |
| `artifact-11-list-delete` | 48 | destructive seed | Do not expose casually; require explicit verification if ever implemented. |
| `artifact-12-list-setup` | 110 | historical-only | One-shot setup evidence; no MCP feature planned. |
| `artifact-13-routine-list-cleanup` | 137 | historical-only | One-shot list cleanup evidence. |
| `artifact-14-legacy-list-migration` | 135 | historical-only | One-shot legacy list migration evidence. |
| `artifact-15-shared-list-extraction` | 176 | historical-only | Shared-list operation; keep out of default automation. |
| `artifact-16-recurring-reminder-seed` | 87 | historical-only | Recurrence seed only if reminder recurrence creation is revisited. |
| `artifact-17-calendar-portfolio-refactor` | 230 | historical-only | High-blast-radius calendar admin; plan/report first if revisited. |
| `artifact-18-checklist-bootstrap` | 267 | historical-only | Checklist bootstrap evidence. |
| `artifact-19-checklist-patch-a` | 124 | historical-only | Checklist patch evidence. |
| `artifact-20-checklist-patch-b` | 125 | historical-only | Checklist patch evidence. |

## Feature Backlog Seeded

The first maintained MCP feature should stay narrow:

- Add bounded reminder diagnostics to read output, including due date
  components, recurrence summaries, and existing completion dates.
- Add historical completion support by extending `create_reminder` and
  `complete_reminder` with a `completion_date` argument.
- Keep current safety posture: default read-only profile, allowlist checks,
  confirmation-token enforcement for mutations, and untrusted wrapping for
  EventKit-derived read output.

Defer list migration, list deletion, shared-list rewrites, and calendar
portfolio changes until separate specs define dry-run behavior, verification
proofs, and destructive policy gates.

## Privacy Rules

- Do not copy the reviewed Swift scripts into this repository.
- Do not commit local vault paths.
- Do not include personal reminder titles, person names, client names, or
  private notes extracted from the scripts.
- Keep this directory as an inventory and decision record only.
