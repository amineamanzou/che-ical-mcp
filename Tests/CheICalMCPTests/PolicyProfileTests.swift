import XCTest
import MCP
@testable import CheICalMCP

final class PolicyProfileTests: XCTestCase {

    func testDefaultProfileIsReadOnly() {
        XCTAssertEqual(ToolPolicy.default.profile, .read)
    }

    func testDefaultToolListExposesOnlyReadTools() {
        let names = Set(CheICalMCPServer.defineTools().map(\.name))

        let expectedReadTools: Set<String> = [
            "list_calendars",
            "list_events",
            "search_events",
            "list_events_quick",
            "check_conflicts",
            "find_duplicate_events",
            "list_reminders",
            "search_reminders",
            "list_reminder_tags",
        ]
        XCTAssertEqual(names, expectedReadTools)
    }

    func testWriteSafeProfileExposesReadAndSafeWriteToolsButNotDestructiveTools() {
        let names = Set(CheICalMCPServer
            .defineTools(policy: ToolPolicy(profile: .writeSafe))
            .map(\.name))

        XCTAssertTrue(names.contains("list_events"))
        XCTAssertTrue(names.contains("create_event"))
        XCTAssertTrue(names.contains("create_reminder"))
        XCTAssertFalse(names.contains("delete_event"))
        XCTAssertFalse(names.contains("cleanup_completed_reminders"))
    }

    func testDestructiveProfileExposesAllMutationTools() {
        let names = Set(CheICalMCPServer
            .defineTools(policy: ToolPolicy(profile: .destructive))
            .map(\.name))

        XCTAssertTrue(names.contains("list_events"))
        XCTAssertTrue(names.contains("create_event"))
        XCTAssertTrue(names.contains("delete_event"))
        XCTAssertTrue(names.contains("delete_events_batch"))
        XCTAssertTrue(names.contains("cleanup_completed_reminders"))
    }

    func testReadProfileDeniesKnownMutationBeforeHandlerValidation() async throws {
        let server = try await CheICalMCPServer(policy: .readOnly)

        do {
            _ = try await server.executeToolCall(name: "create_event", arguments: [:])
            XCTFail("create_event should be denied by read profile")
        } catch ToolError.policyDenied(let name, let profile) {
            XCTAssertEqual(name, "create_event")
            XCTAssertEqual(profile, "read")
        } catch {
            XCTFail("Expected policyDenied, got \(error)")
        }
    }

    func testUnknownToolStillReportsUnknownTool() async throws {
        let server = try await CheICalMCPServer(policy: .readOnly)

        do {
            _ = try await server.executeToolCall(name: "bogus", arguments: [:])
            XCTFail("bogus should be unknown")
        } catch ToolError.unknownTool(let name) {
            XCTAssertEqual(name, "bogus")
        } catch {
            XCTFail("Expected unknownTool, got \(error)")
        }
    }

    func testAuditEntryDoesNotIncludeArguments() {
        let entry = PolicyAuditLogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            decision: "deny",
            profile: "read",
            tool: "delete_event"
        )

        let line = PolicyAuditLogger.format(entry)
        XCTAssertTrue(line.contains("\"decision\":\"deny\""))
        XCTAssertTrue(line.contains("\"profile\":\"read\""))
        XCTAssertTrue(line.contains("\"tool\":\"delete_event\""))
        XCTAssertFalse(line.contains("arguments"))
        XCTAssertFalse(line.contains("title"))
        XCTAssertFalse(line.contains("notes"))
        XCTAssertFalse(line.contains("calendar_name"))
    }

    func testAllowlistDeniesTopLevelCalendarOutsideConfiguredSet() {
        let policy = ToolPolicy(profile: .writeSafe, allowedCalendars: ["Work"])

        XCTAssertNoThrow(try policy.authorize(
            toolName: "create_event",
            arguments: ["calendar_name": .string("Work")]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_event",
            arguments: ["calendar_name": .string("Personal")]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_event")
            XCTAssertEqual(profile, "write_safe")
            XCTAssertFalse(String(describing: error).contains("Personal"))
        }
    }

    func testAllowlistChecksNestedBatchEventCalendarNames() {
        let policy = ToolPolicy(profile: .writeSafe, allowedCalendars: ["Work"])

        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_events_batch",
            arguments: [
                "events": .array([
                    .object([
                        "title": .string("ok"),
                        "start_time": .string("2026-01-01T10:00:00"),
                        "end_time": .string("2026-01-01T11:00:00"),
                        "calendar_name": .string("Personal"),
                    ])
                ])
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_events_batch")
            XCTAssertEqual(profile, "write_safe")
        }
    }

    func testAllowlistDeniesUnscopedCleanupAcrossAllReminderLists() {
        let policy = ToolPolicy(profile: .destructive, allowedCalendars: ["Work"])

        XCTAssertThrowsError(try policy.authorize(
            toolName: "cleanup_completed_reminders",
            arguments: ["dry_run": .bool(false)]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "cleanup_completed_reminders")
            XCTAssertEqual(profile, "destructive")
        }
    }

    func testAllowlistDeniesUnscopedListEventsAcrossAllCalendars() {
        let policy = ToolPolicy(profile: .read, allowedCalendars: ["Work"])

        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_events")
            XCTAssertEqual(profile, "read")
        }
    }

    func testAllowlistDeniesSpoofedScopeForIdOnlyDestructiveTools() {
        let policy = ToolPolicy(profile: .destructive, allowedCalendars: ["Work"])

        let cases: [(tool: String, arguments: [String: Value])] = [
            ("delete_calendar", ["id": .string("calendar-id"), "calendar_name": .string("Work")]),
            ("delete_event", ["event_id": .string("event-id"), "calendar_name": .string("Work")]),
            ("delete_reminder", ["reminder_id": .string("reminder-id"), "calendar_name": .string("Work")]),
            ("delete_reminders_batch", [
                "reminder_ids": .array([.string("reminder-id")]),
                "calendar_name": .string("Work"),
            ]),
            ("cleanup_completed_reminders", [
                "reminder_ids": .array([.string("reminder-id")]),
                "calendar_name": .string("Work"),
            ]),
        ]

        for testCase in cases {
            XCTAssertThrowsError(try policy.authorize(
                toolName: testCase.tool,
                arguments: testCase.arguments
            )) { error in
                guard case ToolError.policyDenied(let name, let profile) = error else {
                    return XCTFail("Expected policyDenied for \(testCase.tool), got \(error)")
                }
                XCTAssertEqual(name, testCase.tool)
                XCTAssertEqual(profile, "destructive")
            }
        }
    }

    func testAllowlistDeniesSpoofedScopeForIdSelectedMutationTools() {
        let policy = ToolPolicy(profile: .destructive, allowedCalendars: ["Work"])

        let cases: [(tool: String, arguments: [String: Value])] = [
            ("update_calendar", ["id": .string("calendar-id"), "title": .string("Work")]),
            ("update_event", ["event_id": .string("event-id"), "calendar_name": .string("Work")]),
            ("update_reminder", ["reminder_id": .string("reminder-id"), "calendar_name": .string("Work")]),
            ("complete_reminder", ["reminder_id": .string("reminder-id"), "calendar_name": .string("Work")]),
            ("copy_event", ["event_id": .string("event-id"), "target_calendar": .string("Work")]),
            ("move_events_batch", [
                "event_ids": .array([.string("event-id")]),
                "target_calendar": .string("Work"),
            ]),
        ]

        for testCase in cases {
            XCTAssertThrowsError(try policy.authorize(
                toolName: testCase.tool,
                arguments: testCase.arguments
            )) { error in
                guard case ToolError.policyDenied(let name, let profile) = error else {
                    return XCTFail("Expected policyDenied for \(testCase.tool), got \(error)")
                }
                XCTAssertEqual(name, testCase.tool)
                XCTAssertEqual(profile, "destructive")
            }
        }
    }

    func testAllowlistDeniesUnusedScopeFieldsForUnscopedTools() {
        let policy = ToolPolicy(profile: .destructive, allowedCalendars: ["Work"])

        let cases: [(tool: String, arguments: [String: Value])] = [
            ("list_calendars", ["calendar_name": .string("Work")]),
            ("find_duplicate_events", [
                "calendar_name": .string("Work"),
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
            ]),
            ("undo", ["calendar_name": .string("Work")]),
            ("redo", ["calendar_name": .string("Work")]),
            ("undo_history", [
                "calendar_name": .string("Work"),
                "limit": .int(10),
            ]),
        ]

        for testCase in cases {
            XCTAssertThrowsError(try policy.authorize(
                toolName: testCase.tool,
                arguments: testCase.arguments
            )) { error in
                guard case ToolError.policyDenied(let name, let profile) = error else {
                    return XCTFail("Expected policyDenied for \(testCase.tool), got \(error)")
                }
                XCTAssertEqual(name, testCase.tool)
                XCTAssertEqual(profile, "destructive")
            }
        }
    }

    func testAllowlistRequiresEveryBatchCreateItemToBeScoped() {
        let policy = ToolPolicy(profile: .writeSafe, allowedCalendars: ["Work"])

        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_events_batch",
            arguments: [
                "events": .array([
                    .object([
                        "title": .string("ok"),
                        "start_time": .string("2026-01-01T10:00:00"),
                        "end_time": .string("2026-01-01T11:00:00"),
                        "calendar_name": .string("Work"),
                    ]),
                    .object([
                        "title": .string("missing scope"),
                        "start_time": .string("2026-01-02T10:00:00"),
                        "end_time": .string("2026-01-02T11:00:00"),
                    ]),
                ])
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_events_batch")
            XCTAssertEqual(profile, "write_safe")
        }

        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_reminders_batch",
            arguments: [
                "reminders": .array([
                    .object([
                        "title": .string("ok"),
                        "calendar_name": .string("Work"),
                    ]),
                    .object([
                        "title": .string("missing scope"),
                    ]),
                ])
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_reminders_batch")
            XCTAssertEqual(profile, "write_safe")
        }
    }

    func testAllowlistAcceptsOnlyToolSpecificScopeFields() {
        let policy = ToolPolicy(profile: .read, allowedCalendars: ["Work"])

        XCTAssertNoThrow(try policy.authorize(
            toolName: "find_duplicate_events",
            arguments: [
                "calendar_names": .array([.string("Work")]),
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "find_duplicate_events",
            arguments: [
                "calendar_names": .array([.string("Personal")]),
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
            ]
        ))
    }

    func testConfirmationTokenRequiredWhenConfiguredForWriteTool() {
        let policy = ToolPolicy(profile: .writeSafe, confirmationToken: "approve-local-write")

        XCTAssertThrowsError(try policy.authorize(toolName: "create_event", arguments: [:])) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_event")
            XCTAssertEqual(profile, "write_safe")
        }

        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_event",
            arguments: ["confirmation_token": .string("wrong")]
        ))
    }

    func testEmptyConfirmationTokenEnvironmentFailsClosed() {
        let policy = ToolPolicy.fromEnvironment([
            "CHE_ICAL_MCP_PROFILE": "write_safe",
            "CHE_ICAL_MCP_CONFIRMATION_TOKEN": " \t ",
        ])

        XCTAssertTrue(policy.configurationErrors.contains("CHE_ICAL_MCP_CONFIRMATION_TOKEN"))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_event",
            arguments: ["calendar_name": .string("Work")]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_event")
            XCTAssertEqual(profile, "write_safe")
        }
    }

    func testConfirmationTokenIsAdvertisedInMutationToolSchemasWhenConfigured() {
        let policy = ToolPolicy(profile: .destructive, confirmationToken: "approve-local-write")
        let tools = Dictionary(uniqueKeysWithValues: CheICalMCPServer
            .defineTools(policy: policy)
            .map { ($0.name, $0) })

        let mutationTools: Set<String> = [
            "create_calendar",
            "update_calendar",
            "create_event",
            "update_event",
            "create_reminder",
            "update_reminder",
            "complete_reminder",
            "create_events_batch",
            "create_reminders_batch",
            "delete_calendar",
            "delete_event",
            "undo",
            "redo",
            "undo_history",
            "delete_reminder",
            "copy_event",
            "move_events_batch",
            "delete_events_batch",
            "delete_reminders_batch",
            "cleanup_completed_reminders",
        ]

        for toolName in mutationTools {
            guard let tool = tools[toolName] else {
                XCTFail("Expected \(toolName) to be exposed")
                continue
            }
            let properties = tool.inputSchema.objectValue?["properties"]?.objectValue
            let required = tool.inputSchema.objectValue?["required"]?.arrayValue ?? []

            XCTAssertNotNil(properties?["confirmation_token"], "\(toolName) should advertise confirmation_token")
            XCTAssertTrue(required.contains { $0.stringValue == "confirmation_token" }, "\(toolName) should require confirmation_token")
        }

        let readProperties = tools["list_events"]?.inputSchema.objectValue?["properties"]?.objectValue
        XCTAssertNil(readProperties?["confirmation_token"])
    }

    func testConfirmationTokenAllowsConfiguredWriteTool() {
        let policy = ToolPolicy(profile: .writeSafe, confirmationToken: "approve-local-write")

        XCTAssertNoThrow(try policy.authorize(
            toolName: "create_event",
            arguments: ["confirmation_token": .string("approve-local-write")]
        ))
        XCTAssertNoThrow(try policy.authorize(toolName: "list_events", arguments: [
            "start_date": .string("2026-01-01"),
            "end_date": .string("2026-01-02"),
        ]))
    }

    func testMaxResultCountDeniesOversizedLimit() {
        let policy = ToolPolicy(profile: .read, maxResultCount: 50)

        XCTAssertNoThrow(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
                "limit": .int(50),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
                "limit": .int(51),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_events")
            XCTAssertEqual(profile, "read")
        }
    }

    func testMaxResultCountRequiresExplicitLimitForLimitAwareTools() {
        let policy = ToolPolicy(profile: .read, maxResultCount: 50)

        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-02"),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_events")
            XCTAssertEqual(profile, "read")
        }
    }

    func testReminderDiagnosticsRemainReadProfileAndRespectResultCap() {
        let policy = ToolPolicy(profile: .read, maxResultCount: 50)

        XCTAssertNoThrow(try policy.authorize(
            toolName: "list_reminders",
            arguments: [
                "include_diagnostics": .bool(true),
                "limit": .int(50),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_reminders",
            arguments: ["include_diagnostics": .bool(true)]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_reminders")
            XCTAssertEqual(profile, "read")
        }
        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_reminders",
            arguments: [
                "include_diagnostics": .bool(true),
                "limit": .int(51),
            ]
        ))
    }

    func testAllowlistDeniesCompleteReminderWithCompletionDateBeforeDispatch() {
        let policy = ToolPolicy(profile: .writeSafe, allowedCalendars: ["Work"])

        XCTAssertThrowsError(try policy.authorize(
            toolName: "complete_reminder",
            arguments: [
                "reminder_id": .string("reminder-id"),
                "completion_date": .string("2026-05-10T12:00:00+02:00"),
                "calendar_name": .string("Work"),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "complete_reminder")
            XCTAssertEqual(profile, "write_safe")
        }
    }

    func testMaxResultCountCapsCleanupReminderIdsInBindingMode() {
        let policy = ToolPolicy(profile: .destructive, maxResultCount: 2)

        XCTAssertNoThrow(try policy.authorize(
            toolName: "cleanup_completed_reminders",
            arguments: [
                "reminder_ids": .array([.string("a"), .string("b")]),
                "limit": .int(1),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "cleanup_completed_reminders",
            arguments: [
                "reminder_ids": .array([.string("a"), .string("b"), .string("c")]),
                "limit": .int(1),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "cleanup_completed_reminders")
            XCTAssertEqual(profile, "destructive")
        }
    }

    func testMaxDateRangeDeniesOversizedRange() {
        let policy = ToolPolicy(profile: .read, maxDateRangeDays: 30)

        XCTAssertNoThrow(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-31"),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-02-01"),
            ]
        ))
    }

    func testMaxDateRangeAppliesOnlyToRangeReadTools() {
        let policy = ToolPolicy(profile: .writeSafe, maxDateRangeDays: 1)

        XCTAssertNoThrow(try policy.authorize(
            toolName: "update_event",
            arguments: [
                "event_id": .string("event-id"),
                "start_time": .string("2026-01-01T10:00:00"),
            ]
        ))
        XCTAssertNoThrow(try policy.authorize(
            toolName: "create_event",
            arguments: [
                "title": .string("long workshop"),
                "start_time": .string("2026-01-01T10:00:00"),
                "end_time": .string("2026-01-03T10:00:00"),
                "calendar_name": .string("Work"),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_events",
            arguments: [
                "start_date": .string("2026-01-01"),
                "end_date": .string("2026-01-03"),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_events")
            XCTAssertEqual(profile, "write_safe")
        }
    }

    func testMaxDateRangeDeniesSearchEventsImplicitDefaultRange() {
        let policy = ToolPolicy(profile: .read, maxDateRangeDays: 30)

        XCTAssertThrowsError(try policy.authorize(
            toolName: "search_events",
            arguments: [
                "keyword": .string("planning"),
                "limit": .int(10),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "search_events")
            XCTAssertEqual(profile, "read")
        }
    }

    func testMaxDateRangeDeniesListEventsQuickRangeAboveConfiguredCap() {
        let policy = ToolPolicy(profile: .read, maxDateRangeDays: 7)

        XCTAssertNoThrow(try policy.authorize(
            toolName: "list_events_quick",
            arguments: [
                "range": .string("next_7_days"),
                "limit": .int(10),
            ]
        ))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "list_events_quick",
            arguments: [
                "range": .string("next_30_days"),
                "limit": .int(10),
            ]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_events_quick")
            XCTAssertEqual(profile, "read")
        }
    }

    func testPolicyFromEnvironmentParsesRuntimeConstraints() {
        let policy = ToolPolicy.fromEnvironment([
            "CHE_ICAL_MCP_PROFILE": "destructive",
            "CHE_ICAL_MCP_ALLOWED_CALENDARS": "Work, Personal",
            "CHE_ICAL_MCP_MAX_DATE_RANGE_DAYS": "14",
            "CHE_ICAL_MCP_MAX_RESULT_COUNT": "25",
            "CHE_ICAL_MCP_CONFIRMATION_TOKEN": "confirm-local",
        ])

        XCTAssertEqual(policy.profile, .destructive)
        XCTAssertEqual(policy.allowedCalendars, ["Work", "Personal"])
        XCTAssertEqual(policy.maxDateRangeDays, 14)
        XCTAssertEqual(policy.maxResultCount, 25)
        XCTAssertEqual(policy.confirmationToken, "confirm-local")
        XCTAssertTrue(policy.configurationErrors.isEmpty)
    }

    func testEmptyCalendarAllowlistEnvironmentFailsClosed() {
        let policy = ToolPolicy.fromEnvironment([
            "CHE_ICAL_MCP_PROFILE": "write_safe",
            "CHE_ICAL_MCP_ALLOWED_CALENDARS": " \t ",
        ])

        XCTAssertTrue(policy.configurationErrors.contains("CHE_ICAL_MCP_ALLOWED_CALENDARS"))
        XCTAssertThrowsError(try policy.authorize(
            toolName: "create_event",
            arguments: ["calendar_name": .string("Work")]
        )) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "create_event")
            XCTAssertEqual(profile, "write_safe")
        }
    }

    func testInvalidRuntimeCapFailsClosed() {
        let policy = ToolPolicy.fromEnvironment([
            "CHE_ICAL_MCP_MAX_RESULT_COUNT": "many",
        ])

        XCTAssertFalse(policy.configurationErrors.isEmpty)
        XCTAssertThrowsError(try policy.authorize(toolName: "list_calendars", arguments: [:])) { error in
            guard case ToolError.policyDenied(let name, let profile) = error else {
                return XCTFail("Expected policyDenied, got \(error)")
            }
            XCTAssertEqual(name, "list_calendars")
            XCTAssertEqual(profile, "read")
        }
    }
}
