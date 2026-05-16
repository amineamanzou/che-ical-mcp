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
