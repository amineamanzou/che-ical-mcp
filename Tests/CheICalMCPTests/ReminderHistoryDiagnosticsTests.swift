import Foundation
import MCP
import XCTest
@testable import CheICalMCP

final class ReminderHistoryDiagnosticsTests: XCTestCase {
    func testListRemindersSchemaAdvertisesOptionalDiagnostics() throws {
        let tool = try Self.tool(named: "list_reminders")
        let properties = try Self.properties(of: tool)
        let required = tool.inputSchema.objectValue?["required"]?.arrayValue ?? []

        XCTAssertEqual(properties["include_diagnostics"]?.objectValue?["type"]?.stringValue, "boolean")
        XCTAssertFalse(required.contains { $0.stringValue == "include_diagnostics" })
    }

    func testCreateAndCompleteReminderSchemasAdvertiseCompletionDateWithoutNewTool() throws {
        let tools = CheICalMCPServer.defineTools(policy: ToolPolicy(profile: .destructive))
        let names = Set(tools.map(\.name))

        XCTAssertFalse(names.contains("create_completed_reminder"))
        XCTAssertFalse(names.contains("complete_reminder_with_date"))
        XCTAssertEqual(try Self.properties(of: Self.tool(named: "create_reminder"))["completion_date"]?.objectValue?["type"]?.stringValue, "string")
        XCTAssertEqual(try Self.properties(of: Self.tool(named: "complete_reminder"))["completion_date"]?.objectValue?["type"]?.stringValue, "string")
    }

    func testListRemindersDefaultResponseOmitsDiagnostics() async throws {
        let fake = FakeReminderOperationsSource()
        await fake.scriptReminders([.sample()])
        let server = try await CheICalMCPServer(reminderOperationsSource: fake, policy: .readOnly)

        let response = try await server.executeToolCall(
            name: "list_reminders",
            arguments: ["limit": .int(10)]
        )
        let reminder = try Self.firstReminder(from: response)

        XCTAssertNil(reminder["diagnostics"])
    }

    func testListRemindersCanIncludeBoundedDiagnostics() async throws {
        let completionDate = Date(timeIntervalSince1970: 1_778_407_200)
        let fake = FakeReminderOperationsSource()
        await fake.scriptReminders([
            .sample(
                dueDateComponents: ReminderDateComponents(
                    year: 2026,
                    month: 5,
                    day: 10,
                    hour: 12,
                    minute: 0,
                    second: nil,
                    timeZoneIdentifier: "Europe/Paris"
                ),
                completionDate: completionDate,
                recurrenceRules: [
                    ["frequency": "weekly", "interval": 1, "days_of_week": [2]]
                ]
            )
        ])
        let server = try await CheICalMCPServer(reminderOperationsSource: fake, policy: .readOnly)

        let response = try await server.executeToolCall(
            name: "list_reminders",
            arguments: [
                "include_diagnostics": .bool(true),
                "limit": .int(10),
            ]
        )
        let reminder = try Self.firstReminder(from: response)
        let diagnostics = try XCTUnwrap(reminder["diagnostics"] as? [String: Any])

        XCTAssertEqual((diagnostics["due_date_components"] as? [String: Any])?["year"] as? Int, 2026)
        XCTAssertEqual(diagnostics["completion_date"] as? String, "2026-05-10T10:00:00Z")
        XCTAssertEqual((diagnostics["recurrence_rules"] as? [[String: Any]])?.first?["frequency"] as? String, "weekly")
    }

    func testDiagnosticReadOutputIsWrappedAsUntrustedContent() async throws {
        let fake = FakeReminderOperationsSource()
        await fake.scriptReminders([.sample(title: "external title")])
        let server = try await CheICalMCPServer(reminderOperationsSource: fake, policy: .readOnly)

        let result = await server.handleToolCallForTesting(
            name: "list_reminders",
            arguments: [
                "include_diagnostics": .bool(true),
                "limit": .int(10),
            ]
        )

        guard case let .text(text, _, _) = result.content.first else {
            return XCTFail("expected text content")
        }
        XCTAssertTrue(text.hasPrefix("[UNTRUSTED CALENDAR DATA"))
        XCTAssertTrue(text.contains(#""diagnostics""#))
    }

    func testCreateReminderWithCompletionDateCreatesCompletedReminder() async throws {
        let fake = FakeReminderOperationsSource()
        let server = try await CheICalMCPServer(
            reminderOperationsSource: fake,
            policy: ToolPolicy(profile: .writeSafe)
        )

        let response = try await server.executeToolCall(
            name: "create_reminder",
            arguments: [
                "title": .string("restored task"),
                "calendar_name": .string("Work"),
                "completion_date": .string("2026-05-10T12:00:00+02:00"),
            ]
        )
        let json = try Self.jsonObject(from: response)
        let calls = await fake.createCalls

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.completionDate, Date(timeIntervalSince1970: 1_778_407_200))
        XCTAssertTrue(calls.first?.completed ?? false)
        XCTAssertEqual(json["completion_date"] as? String, "2026-05-10T10:00:00Z")
    }

    func testCreateReminderRejectsInvalidCompletionDateBeforeWrite() async throws {
        let fake = FakeReminderOperationsSource()
        let server = try await CheICalMCPServer(
            reminderOperationsSource: fake,
            policy: ToolPolicy(profile: .writeSafe)
        )

        do {
            _ = try await server.executeToolCall(
                name: "create_reminder",
                arguments: [
                    "title": .string("restored task"),
                    "calendar_name": .string("Work"),
                    "completion_date": .string("not-a-date"),
                ]
            )
            XCTFail("invalid completion_date should be rejected")
        } catch ToolError.invalidParameter {
            let calls = await fake.createCalls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testCreateReminderRejectsNonStringCompletionDateBeforeWrite() async throws {
        let fake = FakeReminderOperationsSource()
        let server = try await CheICalMCPServer(
            reminderOperationsSource: fake,
            policy: ToolPolicy(profile: .writeSafe)
        )

        do {
            _ = try await server.executeToolCall(
                name: "create_reminder",
                arguments: [
                    "title": .string("restored task"),
                    "calendar_name": .string("Work"),
                    "completion_date": .int(123),
                ]
            )
            XCTFail("non-string completion_date should be rejected")
        } catch ToolError.invalidParameter {
            let calls = await fake.createCalls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testCompleteReminderWithCompletionDateUsesProvidedDate() async throws {
        let fake = FakeReminderOperationsSource()
        let server = try await CheICalMCPServer(
            reminderOperationsSource: fake,
            policy: ToolPolicy(profile: .writeSafe)
        )

        let response = try await server.executeToolCall(
            name: "complete_reminder",
            arguments: [
                "reminder_id": .string("reminder-1"),
                "completed": .bool(true),
                "completion_date": .string("2026-05-10T12:00:00+02:00"),
            ]
        )
        let json = try Self.jsonObject(from: response)
        let calls = await fake.completeCalls

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.completionDate, Date(timeIntervalSince1970: 1_778_407_200))
        XCTAssertEqual(json["completion_date"] as? String, "2026-05-10T10:00:00Z")
    }

    func testCompleteReminderRejectsCompletionDateWhenUncompletingBeforeWrite() async throws {
        let fake = FakeReminderOperationsSource()
        let server = try await CheICalMCPServer(
            reminderOperationsSource: fake,
            policy: ToolPolicy(profile: .writeSafe)
        )

        do {
            _ = try await server.executeToolCall(
                name: "complete_reminder",
                arguments: [
                    "reminder_id": .string("reminder-1"),
                    "completed": .bool(false),
                    "completion_date": .string("2026-05-10T12:00:00+02:00"),
                ]
            )
            XCTFail("completion_date with completed=false should be rejected")
        } catch ToolError.invalidParameter {
            let calls = await fake.completeCalls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    func testCompleteReminderRejectsNonStringCompletionDateBeforeWrite() async throws {
        let fake = FakeReminderOperationsSource()
        let server = try await CheICalMCPServer(
            reminderOperationsSource: fake,
            policy: ToolPolicy(profile: .writeSafe)
        )

        do {
            _ = try await server.executeToolCall(
                name: "complete_reminder",
                arguments: [
                    "reminder_id": .string("reminder-1"),
                    "completion_date": .int(123),
                ]
            )
            XCTFail("non-string completion_date should be rejected")
        } catch ToolError.invalidParameter {
            let calls = await fake.completeCalls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    private static func tool(named name: String) throws -> Tool {
        let tools = CheICalMCPServer.defineTools(policy: ToolPolicy(profile: .destructive))
        return try XCTUnwrap(tools.first { $0.name == name })
    }

    private static func properties(of tool: Tool) throws -> [String: Value] {
        try XCTUnwrap(tool.inputSchema.objectValue?["properties"]?.objectValue)
    }

    private static func firstReminder(from response: String) throws -> [String: Any] {
        let json = try jsonObject(from: response)
        let reminders = try XCTUnwrap(json["reminders"] as? [[String: Any]])
        return try XCTUnwrap(reminders.first)
    }

    private static func jsonObject(from response: String) throws -> [String: Any] {
        let data = Data(response.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor FakeReminderOperationsSource: ReminderOperationsSource {
    struct CreateCall: Equatable {
        let title: String
        let calendarName: String?
        let completed: Bool
        let completionDate: Date?
    }

    struct CompleteCall: Equatable {
        let identifier: String
        let completed: Bool
        let completionDate: Date?
    }

    private var reminders: [ReminderListItem] = []
    private(set) var createCalls: [CreateCall] = []
    private(set) var completeCalls: [CompleteCall] = []

    func scriptReminders(_ reminders: [ReminderListItem]) {
        self.reminders = reminders
    }

    func listReminderItems(
        completed: Bool?,
        calendarName: String?,
        calendarSource: String?
    ) async throws -> [ReminderListItem] {
        reminders
    }

    func createReminderItem(
        title: String,
        notes: String?,
        dueDate: Date?,
        priority: Int,
        calendarName: String?,
        calendarSource: String?,
        recurrenceRule: RecurrenceRuleInput?,
        locationTrigger: LocationTriggerInput?,
        completionDate: Date?
    ) async throws -> ReminderMutationResult {
        createCalls.append(CreateCall(
            title: title,
            calendarName: calendarName,
            completed: completionDate != nil,
            completionDate: completionDate
        ))
        return ReminderMutationResult(
            id: "created-1",
            title: title,
            isCompleted: completionDate != nil,
            completionDate: completionDate,
            isDuplicate: false
        )
    }

    func completeReminderItem(
        identifier: String,
        completed: Bool,
        completionDate: Date?
    ) async throws -> ReminderMutationResult {
        completeCalls.append(CompleteCall(
            identifier: identifier,
            completed: completed,
            completionDate: completionDate
        ))
        return ReminderMutationResult(
            id: identifier,
            title: "completed task",
            isCompleted: completed,
            completionDate: completionDate,
            isDuplicate: false
        )
    }
}

private extension ReminderListItem {
    static func sample(
        id: String = "reminder-1",
        title: String = "Task",
        dueDateComponents: ReminderDateComponents? = nil,
        completionDate: Date? = nil,
        recurrenceRules: [[String: Any]]? = nil
    ) -> ReminderListItem {
        ReminderListItem(
            id: id,
            title: title,
            notes: nil,
            isCompleted: completionDate != nil,
            priority: 0,
            calendarTitle: "Work",
            dueDate: nil,
            dueDateComponents: dueDateComponents,
            completionDate: completionDate,
            creationDate: nil,
            recurrenceRules: recurrenceRules,
            locationTrigger: nil
        )
    }
}
