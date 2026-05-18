# calendar-reminders-policy Specification

## Purpose

Define the local MCP safety policy for Calendar and Reminders access, including
default read-only exposure, pre-dispatch authorization, runtime blast-radius
controls, audit logging, and supply-chain self-update gating.

## Requirements

### Requirement: Default capability profile is read-only

The MCP server SHALL default to a `read` capability profile when no profile is configured.

#### Scenario: Default tool exposure

- **WHEN** an MCP client requests the tool list without setting a capability profile
- **THEN** the returned tools SHALL include only read/search Calendar and Reminders tools
- **AND** it SHALL NOT include create, update, delete, move, batch mutation, cleanup, undo, redo, or self-update capabilities


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/ToolPolicy.swift
-->

---
### Requirement: Policy is enforced before tool dispatch

The MCP server SHALL enforce the active capability profile before dispatching a tool handler.

#### Scenario: Direct mutation call in read profile

- **WHEN** a client directly calls a mutation tool by name while the active profile is `read`
- **THEN** the server SHALL reject the call before invoking the mutation handler
- **AND** the error message SHALL identify policy denial without including EventKit-derived content


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/ToolPolicy.swift
-->

---
### Requirement: EventKit-derived read output is marked untrusted

All read tools that return Calendar or Reminders content, including calendar/list/source names, SHALL wrap model-visible output in an untrusted-data boundary.

#### Scenario: Calendar list output

- **WHEN** `list_calendars` returns calendar, reminder list, or source names
- **THEN** the model-visible MCP response SHALL be wrapped as untrusted calendar data


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/Server.swift
-->

---
### Requirement: Policy decisions are audit logged

The MCP server SHALL maintain a local audit-log path for policy allow/deny decisions.

#### Scenario: Denied mutation

- **WHEN** a mutation tool is denied by policy
- **THEN** the audit entry SHALL include timestamp, decision, profile, and tool name
- **AND** it SHALL NOT include tool arguments, event titles, notes, locations, attendees, calendar names, source names, or reminder list names


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/ToolPolicy.swift
-->

---
### Requirement: Self-update is disabled by default

The self-update command SHALL be disabled unless the operator explicitly enables it for the process.

#### Scenario: Default self-update invocation

- **WHEN** the process receives `--self-update` without the explicit enablement flag
- **THEN** the command SHALL refuse to query GitHub Releases or download assets


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/SelfUpdate.swift
-->

---
### Requirement: Runtime policy can scope accessible calendars and reminder lists

The MCP server SHALL allow operators to configure an allowlist of calendar and reminder list names that applies before tool dispatch.

#### Scenario: Calendar outside allowlist

- **WHEN** a tool call includes a `calendar_name`, `target_calendar`, `calendar_names`, or batch item `calendar_name` outside the configured allowlist
- **THEN** the server SHALL reject the call before invoking the handler
- **AND** the error message SHALL NOT include the supplied calendar or reminder list name

#### Scenario: Missing allowlist scope

- **WHEN** the allowlist is configured and a calendar/list-aware tool call omits a scoped calendar or reminder list argument
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: Unused allowlist scope field

- **WHEN** the allowlist is configured and a tool call includes an otherwise allowed calendar or reminder list field that the selected handler does not use as scope
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: Tool without pre-dispatch scope

- **WHEN** the allowlist is configured and a tool cannot prove calendar or reminder list scope from handler-used arguments before dispatch
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: Partially scoped batch create

- **WHEN** the allowlist is configured and a batch create tool omits `calendar_name` from any item
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: ID-selected mutation with spoofed allowlist scope

- **WHEN** the allowlist is configured and an ID-selected mutation tool call includes an otherwise allowed calendar or reminder list field that the handler does not use as proof of the source scope
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: Binding cleanup with spoofed allowlist scope

- **WHEN** the allowlist is configured and `cleanup_completed_reminders` is called with `reminder_ids`
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: Empty configured allowlist

- **WHEN** the allowlist environment variable is present but empty or whitespace-only
- **THEN** the server SHALL treat it as a configuration error
- **AND** the server SHALL reject tool calls before invoking handlers


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/ToolPolicy.swift
-->

---
### Requirement: Runtime policy can cap read blast radius

The MCP server SHALL allow operators to configure maximum result-count and date-range caps for scoped read tools.

#### Scenario: Oversized read request

- **WHEN** a read tool call supplies a `limit` or date range above the configured policy cap
- **THEN** the server SHALL reject the call before invoking the handler
- **AND** the audit entry SHALL NOT include tool arguments or EventKit-derived content

#### Scenario: Oversized cleanup binding request

- **WHEN** `cleanup_completed_reminders` supplies `reminder_ids` above the configured result-count cap
- **THEN** the server SHALL reject the call before invoking the handler

#### Scenario: Implicit read range

- **WHEN** a read tool would use an implicit date range while a date-range cap is configured
- **THEN** the server SHALL reject the call unless the implicit range is known and within the configured cap

#### Scenario: Mutation event duration

- **WHEN** a write-safe mutation supplies `start_time` and `end_time` values whose duration is above the configured date-range cap
- **THEN** the date-range cap SHALL NOT reject the mutation solely because of that event duration


<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/ToolPolicy.swift
-->

---
### Requirement: Runtime policy can require server-side confirmation for mutations

The MCP server SHALL allow operators to configure a confirmation token required for write-safe and destructive tools.

#### Scenario: Missing or wrong confirmation token

- **WHEN** a write-safe or destructive tool is called and the configured confirmation token is absent or mismatched
- **THEN** the server SHALL reject the call before invoking the handler
- **AND** read-only tools SHALL NOT require that token

#### Scenario: Empty configured confirmation token

- **WHEN** the confirmation token environment variable is present but empty or whitespace-only
- **THEN** the server SHALL treat it as a configuration error
- **AND** the server SHALL reject tool calls before invoking handlers

#### Scenario: Mutation schemas expose confirmation token

- **WHEN** the confirmation token is configured and an MCP client lists tools
- **THEN** write-safe and destructive tool schemas SHALL include a `confirmation_token` input property
- **AND** read-only tool schemas SHALL NOT require that token

<!-- @trace
source: minimal-calendar-reminders-profile
updated: 2026-05-17
code:
  - Sources/CheICalMCP/ToolPolicy.swift
-->
