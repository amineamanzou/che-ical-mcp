## ADDED Requirements

### Requirement: Default capability profile is read-only

The MCP server SHALL default to a `read` capability profile when no profile is configured.

#### Scenario: Default tool exposure

- **WHEN** an MCP client requests the tool list without setting a capability profile
- **THEN** the returned tools SHALL include only read/search Calendar and Reminders tools
- **AND** it SHALL NOT include create, update, delete, move, batch mutation, cleanup, undo, redo, or self-update capabilities

### Requirement: Policy is enforced before tool dispatch

The MCP server SHALL enforce the active capability profile before dispatching a tool handler.

#### Scenario: Direct mutation call in read profile

- **WHEN** a client directly calls a mutation tool by name while the active profile is `read`
- **THEN** the server SHALL reject the call before invoking the mutation handler
- **AND** the error message SHALL identify policy denial without including EventKit-derived content

### Requirement: EventKit-derived read output is marked untrusted

All read tools that return Calendar or Reminders content, including calendar/list/source names, SHALL wrap model-visible output in an untrusted-data boundary.

#### Scenario: Calendar list output

- **WHEN** `list_calendars` returns calendar, reminder list, or source names
- **THEN** the model-visible MCP response SHALL be wrapped as untrusted calendar data

### Requirement: Policy decisions are audit logged

The MCP server SHALL maintain a local audit-log path for policy allow/deny decisions.

#### Scenario: Denied mutation

- **WHEN** a mutation tool is denied by policy
- **THEN** the audit entry SHALL include timestamp, decision, profile, and tool name
- **AND** it SHALL NOT include tool arguments, event titles, notes, locations, attendees, calendar names, source names, or reminder list names

### Requirement: Self-update is disabled by default

The self-update command SHALL be disabled unless the operator explicitly enables it for the process.

#### Scenario: Default self-update invocation

- **WHEN** the process receives `--self-update` without the explicit enablement flag
- **THEN** the command SHALL refuse to query GitHub Releases or download assets
