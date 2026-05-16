## 1. Schema and Policy Contracts

- [ ] 1.1 讓 `ListTools` schema 表達 Keep diagnostics opt-in：`list_reminders` 預設不變且只有 `include_diagnostics: true` 才要求 diagnostics contract；以 schema snapshot/assertion test 驗證 `include_diagnostics` 存在且非 required。
- [ ] 1.2 讓 `create_reminder` 和 `complete_reminder` schema 表達 Extend existing reminder tools instead of adding a new tool：兩個既有 tool 暴露 `completion_date`，且沒有新增 dedicated historical-completion tool；以 tool list/schema test 驗證。
- [ ] 1.3 保持 Reminder reads can include bounded diagnostics 的 read policy：`list_reminders` 在 read profile 可用，且 `CHE_ICAL_MCP_MAX_RESULT_COUNT` 對 diagnostics call 仍要求合規 `limit`；以 `PolicyProfileTests` 驗證。
- [ ] 1.4 保持 Preserve current allowlist fail-closed behavior for ID-selected mutations：allowlist 啟用時 `complete_reminder` 加 `completion_date` 仍在 pre-dispatch 被拒絕；以 `PolicyProfileTests` 驗證。

## 2. Reminder Diagnostics Read Behavior

- [ ] 2.1 實作 Reminder reads can include bounded diagnostics：`list_reminders` 未帶 `include_diagnostics` 時 response shape 不含 `diagnostics`；以 handler/unit test 驗證 default response。
- [ ] 2.2 實作 Keep diagnostics opt-in：`list_reminders(include_diagnostics: true)` 每筆 reminder 回傳 bounded `diagnostics` object，包含可用的 due date components、completion date、recurrence summaries；以 fake/EventKit seam test 驗證欄位 shape。
- [ ] 2.3 確認 diagnostics read output 沿用 untrusted wrapping：MCP read response 仍經既有 untrusted wrapper；以 existing read wrapper test 或新增 regression test 驗證。

## 3. Historical Completion Writes

- [ ] 3.1 實作 Historical completion date can be set when creating reminders：`create_reminder(completion_date: ...)` 會建立 completed reminder 並回傳 saved `completion_date`；以 EventKitManager/handler test 驗證。
- [ ] 3.2 實作 create validation：`create_reminder` 對 unparsable `completion_date` 在 EventKit write 前回傳 invalid-parameter error；以 unit/handler test 驗證沒有呼叫 save。
- [ ] 3.3 實作 Historical completion date can be set when completing reminders：`complete_reminder(completed: true, completion_date: ...)` 使用指定時間而非 `Date()`；以 EventKitManager/handler test 驗證。
- [ ] 3.4 實作 contradictory-input guard：`complete_reminder(completed: false, completion_date: ...)` 在 EventKit mutation 前回傳 invalid-parameter error；以 unit/handler test 驗證。

## 4. Verification and Documentation

- [ ] 4.1 完成 EventKit completion-date persistence is verified 並落實 Treat EventKit completion date persistence as a verified behavior：新增 disposable reminder list 的 live/manual verification steps，驗證 write-readback 的 `completionDate` persistence；以 docs review 驗證步驟可執行且不含私人資料。
- [ ] 4.2 更新 README tool reference：document `include_diagnostics` 和 `completion_date` 行為、policy expectations、manual live check；以 docs content review 驗證。
- [ ] 4.3 跑完整 verification：`swift test --filter PolicyProfileTests`、相關 reminder tests、`swift test`、`make release` 全部通過；以命令 exit code 驗證。
