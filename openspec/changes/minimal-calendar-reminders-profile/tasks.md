## 1. Policy and Tool Surface

- [x] 1.1 Add a central policy model with default `read` profile and explicit read/write/destructive tool sets.
- [x] 1.2 Filter default tool exposure so `ListTools` returns read-only Calendar/Reminders tools.
- [x] 1.3 Enforce the policy before dispatching every tool call, including hidden direct calls.

## 2. Prompt-Injection and Audit

- [x] 2.1 Treat `list_calendars` output as untrusted EventKit-derived content.
- [x] 2.2 Add a local audit-log skeleton for allow/deny decisions without storing EventKit text fields.

## 3. Supply Chain

- [x] 3.1 Disable `--self-update` by default and require explicit opt-in via environment.

## 4. Verification

- [x] 4.1 Add tests covering default tool exposure, denied mutations, audit formatting, untrusted wrapping, and self-update gating.
- [x] 4.2 Run the Swift test/build commands available in the local toolchain and document any environment blockers.
