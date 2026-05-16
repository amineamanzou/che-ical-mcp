## Context

這個 change 來自一批本機 EventKit Swift 腳本的整理。腳本顯示出三個可維護需求：讀取 completed reminders、理解 reminder 的 due/recurrence/completion 欄位，以及在重建歷史時設定 completion date。

目前 MCP fork 已經有 policy layer：預設 read-only、write/destructive profile、calendar allowlist、result/date caps、confirmation token、audit log skeleton。新功能必須沿用這些邊界，而不是繞過 policy。

## Goals / Non-Goals

**Goals:**

- 讓 `list_reminders` 可以 opt in 回傳 bounded diagnostic metadata。
- 讓 `create_reminder` 和 `complete_reminder` 可以設定歷史 `completion_date`。
- 保持預設工具面不擴張成新的 destructive workflow。
- 為 EventKit completion-date persistence 留下可驗證的 manual/live check。

**Non-Goals:**

- 不搬移、clone、刪除 reminder lists。
- 不新增 dedicated historical-completion MCP tool。
- 不把本機 vault scripts 複製進 source tree。
- 不改變 default `read` profile 的 mutation exposure。

## Decisions

### Extend existing reminder tools instead of adding a new tool

`create_reminder` 已經負責 reminder creation，`complete_reminder` 已經負責 completion state transition。新增獨立 tool 會增加 MCP surface，且需要額外 policy/schemas/docs。這次選擇在既有 tools 上加 arguments，讓 client 的 mental model 保持簡單。

### Keep diagnostics opt-in

`list_reminders` 目前已有穩定 response shape。Diagnostics 可能增加欄位量與 EventKit-derived details，所以使用 `include_diagnostics: true` opt-in。預設 response 不變。

### Preserve current allowlist fail-closed behavior for ID-selected mutations

`complete_reminder` 是 ID-selected mutation。現有 policy 在 calendar allowlist 啟用時會 fail closed，因為 pre-dispatch 無法證明 source list。這次不新增 pre-dispatch ID resolution；未來若要解除限制，必須另外設計 source-resolution policy。

### Treat EventKit completion date persistence as a verified behavior

EventKit 對 `completionDate` 的 iCloud persistence 需要實機驗證。Unit tests 應 cover parsing、schema、policy、handler response；live check 則用 disposable reminder list 驗證 write-readback。

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
