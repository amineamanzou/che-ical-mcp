import Foundation
import MCP

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
    let allowedCalendars: Set<String>?
    let maxDateRangeDays: Int?
    let maxResultCount: Int?
    let confirmationToken: String?
    let configurationErrors: Set<String>

    static let `default` = ToolPolicy.fromEnvironment()
    static let readOnly = ToolPolicy(profile: .read)

    init(
        profile: ToolCapabilityProfile,
        allowedCalendars: Set<String>? = nil,
        maxDateRangeDays: Int? = nil,
        maxResultCount: Int? = nil,
        confirmationToken: String? = nil,
        configurationErrors: Set<String> = []
    ) {
        self.profile = profile
        self.allowedCalendars = allowedCalendars
        self.maxDateRangeDays = maxDateRangeDays
        self.maxResultCount = maxResultCount
        self.confirmationToken = confirmationToken
        self.configurationErrors = configurationErrors
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> ToolPolicy {
        var configurationErrors = Set<String>()
        return ToolPolicy(
            profile: .fromEnvironment(environment),
            allowedCalendars: allowedCalendars(from: environment["CHE_ICAL_MCP_ALLOWED_CALENDARS"]),
            maxDateRangeDays: positiveInt(
                from: environment["CHE_ICAL_MCP_MAX_DATE_RANGE_DAYS"],
                key: "CHE_ICAL_MCP_MAX_DATE_RANGE_DAYS",
                configurationErrors: &configurationErrors
            ),
            maxResultCount: positiveInt(
                from: environment["CHE_ICAL_MCP_MAX_RESULT_COUNT"],
                key: "CHE_ICAL_MCP_MAX_RESULT_COUNT",
                configurationErrors: &configurationErrors
            ),
            confirmationToken: nonEmptyString(from: environment["CHE_ICAL_MCP_CONFIRMATION_TOKEN"]),
            configurationErrors: configurationErrors
        )
    }

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

    func authorize(toolName: String, arguments: [String: Value] = [:]) throws {
        guard Self.knownTools.contains(toolName) else {
            throw ToolError.unknownTool(toolName)
        }
        guard allowedTools.contains(toolName) else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
        guard configurationErrors.isEmpty else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }

        try enforceConfirmation(toolName: toolName, arguments: arguments)
        try enforceCalendarAllowlist(toolName: toolName, arguments: arguments)
        try enforceMaxResultCount(toolName: toolName, arguments: arguments)
        try enforceMaxDateRange(toolName: toolName, arguments: arguments)
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

    private static func allowedCalendars(from raw: String?) -> Set<String>? {
        guard let raw else { return nil }
        let names = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? nil : Set(names)
    }

    private static func positiveInt(
        from raw: String?,
        key: String,
        configurationErrors: inout Set<String>
    ) -> Int? {
        guard let value = nonEmptyString(from: raw) else { return nil }
        guard let parsed = Int(value), parsed > 0 else {
            configurationErrors.insert(key)
            return nil
        }
        return parsed
    }

    private static func nonEmptyString(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func enforceConfirmation(toolName: String, arguments: [String: Value]) throws {
        guard let confirmationToken,
              Self.writeSafeTools.contains(toolName) || Self.destructiveTools.contains(toolName)
        else {
            return
        }
        guard arguments["confirmation_token"]?.stringValue == confirmationToken else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
    }

    private func enforceCalendarAllowlist(toolName: String, arguments: [String: Value]) throws {
        guard let allowedCalendars else { return }

        for calendarName in try calendarNamesToCheck(toolName: toolName, arguments: arguments) {
            guard allowedCalendars.contains(calendarName) else {
                throw ToolError.policyDenied(name: toolName, profile: profileName)
            }
        }
    }

    private func calendarNamesToCheck(toolName: String, arguments: [String: Value]) throws -> [String] {
        var names: [String] = []

        try appendStringArgument("calendar_name", from: arguments, toolName: toolName, to: &names)
        try appendStringArgument("target_calendar", from: arguments, toolName: toolName, to: &names)
        try appendStringArrayArgument("calendar_names", from: arguments, toolName: toolName, to: &names)

        if toolName == "create_calendar" || toolName == "update_calendar" {
            try appendStringArgument("title", from: arguments, toolName: toolName, to: &names)
        }

        try appendBatchCalendarNames("events", from: arguments, toolName: toolName, to: &names)
        try appendBatchCalendarNames("reminders", from: arguments, toolName: toolName, to: &names)

        return names
    }

    private func appendStringArgument(
        _ key: String,
        from arguments: [String: Value],
        toolName: String,
        to names: inout [String]
    ) throws {
        guard let raw = arguments[key] else { return }
        guard let value = Self.nonEmptyString(from: raw.stringValue) else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
        names.append(value)
    }

    private func appendStringArrayArgument(
        _ key: String,
        from arguments: [String: Value],
        toolName: String,
        to names: inout [String]
    ) throws {
        guard let raw = arguments[key] else { return }
        guard let array = raw.arrayValue else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
        for value in array {
            guard let name = Self.nonEmptyString(from: value.stringValue) else {
                throw ToolError.policyDenied(name: toolName, profile: profileName)
            }
            names.append(name)
        }
    }

    private func appendBatchCalendarNames(
        _ key: String,
        from arguments: [String: Value],
        toolName: String,
        to names: inout [String]
    ) throws {
        guard let raw = arguments[key] else { return }
        guard let array = raw.arrayValue else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
        for value in array {
            guard let object = value.objectValue else {
                throw ToolError.policyDenied(name: toolName, profile: profileName)
            }
            try appendStringArgument("calendar_name", from: object, toolName: toolName, to: &names)
        }
    }

    private func enforceMaxResultCount(toolName: String, arguments: [String: Value]) throws {
        guard let maxResultCount,
              Self.limitAwareTools.contains(toolName)
        else {
            return
        }
        guard let rawLimit = arguments["limit"] else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
        guard let limit = Self.intValue(rawLimit), limit <= maxResultCount else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
    }

    private static let limitAwareTools: Set<String> = [
        "list_events",
        "search_events",
        "list_events_quick",
        "list_reminders",
        "search_reminders",
        "cleanup_completed_reminders",
    ]

    private static func intValue(_ value: Value) -> Int? {
        if let n = value.intValue { return n }
        if let d = value.doubleValue,
           d.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(exactly: d)
        }
        return nil
    }

    private func enforceMaxDateRange(toolName: String, arguments: [String: Value]) throws {
        guard let maxDateRangeDays else { return }

        try enforceDateRangePair(
            toolName: toolName,
            arguments: arguments,
            startKey: "start_date",
            endKey: "end_date",
            maxDateRangeDays: maxDateRangeDays
        )
        try enforceDateRangePair(
            toolName: toolName,
            arguments: arguments,
            startKey: "start_time",
            endKey: "end_time",
            maxDateRangeDays: maxDateRangeDays
        )
        try enforceDateRangePair(
            toolName: toolName,
            arguments: arguments,
            startKey: "after_date",
            endKey: "before_date",
            maxDateRangeDays: maxDateRangeDays
        )
    }

    private func enforceDateRangePair(
        toolName: String,
        arguments: [String: Value],
        startKey: String,
        endKey: String,
        maxDateRangeDays: Int
    ) throws {
        guard arguments[startKey] != nil || arguments[endKey] != nil else { return }
        guard let startRaw = arguments[startKey]?.stringValue,
              let endRaw = arguments[endKey]?.stringValue,
              let start = Self.parsePolicyDate(startRaw),
              let end = Self.parsePolicyDate(endRaw),
              end >= start
        else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }

        let interval = end.timeIntervalSince(start)
        guard interval <= Double(maxDateRangeDays) * 24 * 60 * 60 else {
            throw ToolError.policyDenied(name: toolName, profile: profileName)
        }
    }

    private static func parsePolicyDate(_ string: String) -> Date? {
        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetFormatter.date(from: string) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        if string.count == 10 && string.contains("-") && !string.contains("T") {
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: string)
        }

        if string.contains("T") && !string.contains("+") && !string.hasSuffix("Z") {
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter.date(from: string)
        }

        if !string.contains("-") && string.contains(":") {
            let parts = string.split(separator: ":")
            guard parts.count >= 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else {
                return nil
            }
            let second = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(secondsFromGMT: 0)
            components.year = 2000
            components.month = 1
            components.day = 1
            components.hour = hour
            components.minute = minute
            components.second = second
            return components.date
        }

        return nil
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
