## Context

This change comes from reviewing a set of local EventKit Swift scripts. Those scripts showed three maintainable needs: reading completed reminders, understanding reminder due/recurrence/completion fields, and setting completion dates when reconstructing history.

The MCP fork now has a policy layer: default read-only behavior, write/destructive profiles, calendar allowlists, result/date caps, confirmation tokens, and an audit-log skeleton. New functionality must use those boundaries instead of bypassing policy.

## Goals / Non-Goals

**Goals:**

- Allow `list_reminders` to opt in to bounded diagnostic metadata.
- Allow `create_reminder` and `complete_reminder` to set historical `completion_date` values.
- Keep the default tool surface from expanding into a new destructive workflow.
- Leave a verifiable manual/live check for EventKit completion-date persistence.

**Non-Goals:**

- Do not move, clone, or delete reminder lists.
- Do not add a dedicated historical-completion MCP tool.
- Do not copy local vault scripts into the source tree.
- Do not change mutation exposure for the default `read` profile.

## Decisions

### Extend existing reminder tools instead of adding a new tool

`create_reminder` already owns reminder creation, and `complete_reminder` already owns completion state transitions. Adding a separate tool would expand the MCP surface and require additional policy, schema, and documentation work. This change adds arguments to existing tools so the client mental model stays simple.

### Keep diagnostics opt-in

`list_reminders` already has a stable response shape. Diagnostics can increase field volume and expose additional EventKit-derived details, so they are gated behind `include_diagnostics: true`. The default response remains unchanged.

### Preserve current allowlist fail-closed behavior for ID-selected mutations

`complete_reminder` is an ID-selected mutation. The existing policy fails closed when calendar allowlists are enabled because source list scope cannot be proven before dispatch. This change does not add pre-dispatch ID resolution; lifting that restriction later requires a separate source-resolution policy design.

### Treat EventKit completion date persistence as a verified behavior

EventKit `completionDate` persistence through iCloud needs live verification. Unit tests should cover parsing, schema, policy, and handler response behavior; a live check should use a disposable reminder list to verify write-readback.

## Implementation Contract

`list_reminders`:

- Add `include_diagnostics: boolean`, default `false`.
- When false or absent, keep current per-reminder shape.
- When true, add `diagnostics` per reminder with only bounded structured fields:
  `due_date_components`, `completion_date`, `completion_date_local`, and
  `recurrence_rules` when EventKit provides them.
- Continue to use existing filter, sort, limit, calendar_name, and calendar_source semantics.

`create_reminder`:

- Add optional `completion_date: string`.
- Parse using the existing flexible date parsing path.
- If present, save the reminder as completed and set EventKit `completionDate`.
- Return `completion_date` in the action result when the created reminder is completed by this argument.
- Keep `write_safe` classification and existing allowlist/confirmation behavior.

`complete_reminder`:

- Add optional `completion_date: string`.
- Accept it only when `completed` is absent/defaulted to true or explicitly true.
- Reject `completion_date` with `completed: false` before EventKit mutation.
- Set EventKit `completionDate` from the parsed date instead of always using `Date()`.
- Return `completion_date` when present and saved.

Failure modes:

- Invalid `completion_date` returns invalid-parameter error.
- `completion_date` plus `completed: false` returns invalid-parameter error.
- Calendar allowlist plus ID-selected `complete_reminder` remains policy-denied before dispatch.

Acceptance:

- Policy tests cover read/write exposure, confirmation token schema, and allowlist fail-closed behavior.
- Handler/unit tests cover diagnostics response shape and completion-date validation.
- A documented live check verifies EventKit write-readback on a disposable list.

## Risks / Trade-offs

- EventKit may normalize or drop historical completion dates after sync → document live check and avoid claiming iCloud persistence without evidence.
- Diagnostics can expose more EventKit-derived content → keep opt-in, bounded, and under existing untrusted read wrapping.
- Extending existing tools creates optional argument complexity → keep validation narrow and reject contradictory inputs before mutation.
