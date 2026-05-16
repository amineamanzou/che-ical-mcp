## ADDED Requirements

### Requirement: Reminder reads can include bounded diagnostics

The MCP server SHALL allow `list_reminders` callers to opt in to diagnostic
metadata for reminder due date components, recurrence rules, and completion
state without changing the default response shape.

#### Scenario: Default reminder listing remains unchanged

- **WHEN** `list_reminders` is called without `include_diagnostics`
- **THEN** each returned reminder SHALL use the existing non-diagnostic fields
- **AND** the response SHALL NOT include `diagnostics`

#### Scenario: Diagnostics are returned when requested

- **WHEN** `list_reminders` is called with `include_diagnostics: true`
- **THEN** each returned reminder SHALL include a `diagnostics` object
- **AND** the `diagnostics` object SHALL include due date component fields when present
- **AND** the `diagnostics` object SHALL include recurrence rule summaries when present
- **AND** the `diagnostics` object SHALL include completion date fields when present

#### Scenario: Diagnostics preserve read blast-radius controls

- **WHEN** `CHE_ICAL_MCP_MAX_RESULT_COUNT` is configured
- **AND** `list_reminders` is called with `include_diagnostics: true`
- **THEN** the call SHALL still require a `limit` at or below the configured cap

### Requirement: Historical completion date can be set when creating reminders

The MCP server SHALL allow `create_reminder` to create an already-completed
reminder with an explicit historical completion date.

#### Scenario: Create completed reminder with completion date

- **WHEN** `create_reminder` is called with `completion_date`
- **THEN** the created reminder SHALL be saved as completed
- **AND** its EventKit `completionDate` SHALL be set from `completion_date`
- **AND** the response SHALL include `completion_date`

#### Scenario: Invalid completion date is rejected before EventKit write

- **WHEN** `create_reminder` is called with an unparsable `completion_date`
- **THEN** the server SHALL reject the call before saving a reminder
- **AND** the error SHALL be an invalid-parameter error

#### Scenario: Creation keeps write-safe policy

- **WHEN** `create_reminder` is called with `completion_date`
- **THEN** the tool SHALL remain classified as `write_safe`
- **AND** configured confirmation-token enforcement SHALL apply
- **AND** configured calendar allowlists SHALL apply through `calendar_name`

### Requirement: Historical completion date can be set when completing reminders

The MCP server SHALL allow `complete_reminder` to mark a reminder completed with
an explicit completion date.

#### Scenario: Complete reminder with completion date

- **WHEN** `complete_reminder` is called with `completed: true` and `completion_date`
- **THEN** the reminder SHALL be saved as completed
- **AND** its EventKit `completionDate` SHALL be set from `completion_date`
- **AND** the response SHALL include `completion_date`

#### Scenario: Completion date is rejected when uncompleting

- **WHEN** `complete_reminder` is called with `completed: false` and `completion_date`
- **THEN** the server SHALL reject the call before saving the reminder
- **AND** the error SHALL be an invalid-parameter error

#### Scenario: ID-selected allowlist behavior remains fail-closed

- **WHEN** calendar allowlists are configured
- **AND** `complete_reminder` is called with `completion_date`
- **THEN** the existing ID-selected mutation restriction SHALL still apply before dispatch

### Requirement: EventKit completion-date persistence is verified

The implementation SHALL include a documented verification path for whether
EventKit persists `completionDate` values supplied during create and complete
operations.

#### Scenario: Automated tests cover server-side behavior

- **WHEN** the feature is implemented
- **THEN** unit or handler tests SHALL verify schema exposure, validation, policy classification, and response shape

##### Example: automated coverage targets

| Behavior | Expected test evidence |
| ----- | ----- |
| `list_reminders(include_diagnostics: true)` | Handler test asserts diagnostic fields are present |
| `create_reminder(completion_date: "2026-05-10T12:00:00+02:00")` | Handler or manager test asserts completed state and completion date |
| `complete_reminder(completed: false, completion_date: "2026-05-10T12:00:00+02:00")` | Validation test asserts invalid-parameter error before mutation |

#### Scenario: Live EventKit persistence check is documented

- **WHEN** EventKit persistence cannot be proven with unit tests alone
- **THEN** the implementation SHALL document a local manual check using a disposable reminder list
- **AND** the check SHALL verify that the saved completion date can be read back after the write

##### Example: manual disposable-list check

- **GIVEN** a disposable reminder list and a completion date value `2026-05-10T12:00:00+02:00`
- **WHEN** the operator creates or completes a reminder with that completion date
- **THEN** a subsequent read from EventKit returns the same completion date value
