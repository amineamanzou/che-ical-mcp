## 1. Schema and Policy Contracts

- [ ] 1.1 Express Keep diagnostics opt-in in the `ListTools` schema: `list_reminders` remains unchanged by default and only `include_diagnostics: true` requests the diagnostics contract; verify with a schema snapshot/assertion test that `include_diagnostics` exists and is not required.
- [ ] 1.2 Express Extend existing reminder tools instead of adding a new tool in the `create_reminder` and `complete_reminder` schemas: both existing tools expose `completion_date`, and no dedicated historical-completion tool is added; verify with a tool list/schema test.
- [ ] 1.3 Preserve the read policy for Reminder reads can include bounded diagnostics: `list_reminders` remains available in the read profile, and `CHE_ICAL_MCP_MAX_RESULT_COUNT` still requires a compliant `limit` for diagnostics calls; verify with `PolicyProfileTests`.
- [ ] 1.4 Preserve current allowlist fail-closed behavior for ID-selected mutations: when allowlists are enabled, `complete_reminder` with `completion_date` is still denied before dispatch; verify with `PolicyProfileTests`.

## 2. Reminder Diagnostics Read Behavior

- [ ] 2.1 Implement Reminder reads can include bounded diagnostics: when `list_reminders` omits `include_diagnostics`, the response shape does not include `diagnostics`; verify the default response with a handler/unit test.
- [ ] 2.2 Implement Keep diagnostics opt-in: `list_reminders(include_diagnostics: true)` returns a bounded `diagnostics` object for each reminder, including available due date components, completion date, and recurrence summaries; verify field shape with a fake/EventKit seam test.
- [ ] 2.3 Confirm diagnostic read output uses existing untrusted wrapping: MCP read responses still pass through the existing untrusted wrapper; verify with an existing read-wrapper test or a new regression test.

## 3. Historical Completion Writes

- [ ] 3.1 Implement Historical completion date can be set when creating reminders: `create_reminder(completion_date: ...)` creates a completed reminder and returns the saved `completion_date`; verify with an EventKitManager/handler test.
- [ ] 3.2 Implement create validation: `create_reminder` returns an invalid-parameter error for an unparsable `completion_date` before any EventKit write; verify with a unit/handler test that save is not called.
- [ ] 3.3 Implement Historical completion date can be set when completing reminders: `complete_reminder(completed: true, completion_date: ...)` uses the specified time instead of `Date()`; verify with an EventKitManager/handler test.
- [ ] 3.4 Implement the contradictory-input guard: `complete_reminder(completed: false, completion_date: ...)` returns an invalid-parameter error before any EventKit mutation; verify with a unit/handler test.

## 4. Verification and Documentation

- [ ] 4.1 Complete EventKit completion-date persistence is verified and implement Treat EventKit completion date persistence as a verified behavior: add live/manual verification steps for a disposable reminder list that verify `completionDate` write-readback persistence; verify by docs review that the steps are executable and contain no private data.
- [ ] 4.2 Update the README tool reference: document `include_diagnostics` and `completion_date` behavior, policy expectations, and the manual live check; verify with docs content review.
- [ ] 4.3 Run full verification: `swift test --filter PolicyProfileTests`, relevant reminder tests, `swift test`, and `make release` all pass; verify by command exit code.
