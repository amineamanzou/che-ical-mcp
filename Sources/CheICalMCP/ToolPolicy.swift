import Foundation

enum ToolCapabilityProfile: String, Sendable {
    case read
    case writeSafe = "write_safe"
    case destructive

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> ToolCapabilityProfile {
        guard let raw = environment["CHE_ICAL_MCP_PROFILE"]?.lowercased(),
              let profile = ToolCapabilityProfile(rawValue: raw) else {
            return .read
        }
        return profile
    }
}

struct ToolPolicy: Sendable {
    let profile: ToolCapabilityProfile

    static let `default` = ToolPolicy(profile: .fromEnvironment())
    static let readOnly = ToolPolicy(profile: .read)

    private static let readTools: Set<String> = [
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

    private static let writeSafeTools: Set<String> = [
        "create_calendar",
        "update_calendar",
        "create_event",
        "update_event",
        "create_reminder",
        "update_reminder",
        "complete_reminder",
        "create_events_batch",
        "create_reminders_batch",
    ]

    private static let destructiveTools: Set<String> = [
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

    static let knownTools: Set<String> = readTools
        .union(writeSafeTools)
        .union(destructiveTools)

    var profileName: String {
        profile.rawValue
    }

    func shouldExpose(toolName: String) -> Bool {
        allowedTools.contains(toolName)
    }

    func authorize(toolName: String) throws {
        guard Self.knownTools.contains(toolName) else {
            throw ToolError.unknownTool(toolName)
        }
        guard allowedTools.contains(toolName) else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
    }

    private var allowedTools: Set<String> {
        switch profile {
        case .read:
            return Self.readTools
        case .writeSafe:
            return Self.readTools.union(Self.writeSafeTools)
        case .destructive:
            return Self.knownTools
        }
    }
}

struct PolicyAuditLogEntry: Sendable {
    let timestamp: Date
    let decision: String
    let profile: String
    let tool: String
}

struct PolicyAuditLogger: Sendable {
    let path: String

    static let `default` = PolicyAuditLogger(
        path: ProcessInfo.processInfo.environment["CHE_ICAL_MCP_AUDIT_LOG"]
            ?? FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CheICalMCP/audit.log")
                .path
    )

    static func format(_ entry: PolicyAuditLogEntry) -> String {
        let formatter = ISO8601DateFormatter()
        let payload = [
            "decision": entry.decision,
            "profile": entry.profile,
            "timestamp": formatter.string(from: entry.timestamp),
            "tool": entry.tool,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            return line
        }
        return #"{"decision":"audit_format_error"}"#
    }

    func record(decision: String, profile: String, tool: String) {
        let entry = PolicyAuditLogEntry(
            timestamp: Date(),
            decision: decision,
            profile: profile,
            tool: tool
        )
        let line = Self.format(entry) + "\n"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }
}
