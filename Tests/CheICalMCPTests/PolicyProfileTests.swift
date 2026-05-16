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
}
