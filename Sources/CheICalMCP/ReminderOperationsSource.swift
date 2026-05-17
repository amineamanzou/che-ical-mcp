import EventKit
import Foundation

protocol ReminderOperationsSource {
    func listReminderItems(
        completed: Bool?,
        calendarName: String?,
        calendarSource: String?
    ) async throws -> [ReminderListItem]

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
    ) async throws -> ReminderMutationResult

    func completeReminderItem(
        identifier: String,
        completed: Bool,
        completionDate: Date?
    ) async throws -> ReminderMutationResult
}

struct ReminderDateComponents {
    let year: Int?
    let month: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?
    let second: Int?
    let timeZoneIdentifier: String?

    init(
        year: Int?,
        month: Int?,
        day: Int?,
        hour: Int?,
        minute: Int?,
        second: Int?,
        timeZoneIdentifier: String?
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(_ components: DateComponents?) {
        year = components?.year
        month = components?.month
        day = components?.day
        hour = components?.hour
        minute = components?.minute
        second = components?.second
        timeZoneIdentifier = components?.timeZone?.identifier
    }

    var json: [String: Any] {
        var dict: [String: Any] = [:]
        if let year { dict["year"] = year }
        if let month { dict["month"] = month }
        if let day { dict["day"] = day }
        if let hour { dict["hour"] = hour }
        if let minute { dict["minute"] = minute }
        if let second { dict["second"] = second }
        if let timeZoneIdentifier { dict["time_zone"] = timeZoneIdentifier }
        return dict
    }
}

struct ReminderListItem {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let priority: Int
    let calendarTitle: String
    let dueDate: Date?
    let dueDateComponents: ReminderDateComponents?
    let completionDate: Date?
    let creationDate: Date?
    let recurrenceRules: [[String: Any]]?
    let locationTrigger: [String: Any]?
}

struct ReminderMutationResult {
    let id: String
    let title: String
    let isCompleted: Bool
    let completionDate: Date?
    let isDuplicate: Bool
}

extension EventKitManager: ReminderOperationsSource {
    func listReminderItems(
        completed: Bool?,
        calendarName: String?,
        calendarSource: String?
    ) async throws -> [ReminderListItem] {
        let reminders = try await listReminders(
            completed: completed,
            calendarName: calendarName,
            calendarSource: calendarSource
        )
        return reminders.map(Self.reminderListItem)
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
        let result = try await createReminder(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            calendarName: calendarName,
            calendarSource: calendarSource,
            recurrenceRule: recurrenceRule,
            locationTrigger: locationTrigger,
            completionDate: completionDate
        )
        return ReminderMutationResult(
            id: result.reminder.calendarItemIdentifier,
            title: result.reminder.title ?? title,
            isCompleted: result.reminder.isCompleted,
            completionDate: result.reminder.completionDate,
            isDuplicate: result.isDuplicate
        )
    }

    func completeReminderItem(
        identifier: String,
        completed: Bool,
        completionDate: Date?
    ) async throws -> ReminderMutationResult {
        let reminder = try await completeReminder(
            identifier: identifier,
            completed: completed,
            completionDate: completionDate
        )
        return ReminderMutationResult(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            isDuplicate: false
        )
    }

    private static func reminderListItem(_ reminder: EKReminder) -> ReminderListItem {
        ReminderListItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            calendarTitle: reminder.calendar.title,
            dueDate: safeDateFromComponents(reminder.dueDateComponents),
            dueDateComponents: reminder.dueDateComponents == nil ? nil : ReminderDateComponents(reminder.dueDateComponents),
            completionDate: reminder.completionDate,
            creationDate: reminder.creationDate,
            recurrenceRules: reminder.recurrenceRules?.map {
                formatRecurrenceRule($0, dateFormatter: eventFormattingDateFormatter)
            },
            locationTrigger: Self.locationTrigger(from: reminder)
        )
    }

    private static func locationTrigger(from reminder: EKReminder) -> [String: Any]? {
        guard let alarms = reminder.alarms else { return nil }
        for alarm in alarms {
            guard let structured = alarm.structuredLocation else { continue }
            var triggerDict: [String: Any] = ["title": structured.title ?? ""]
            if let geo = structured.geoLocation {
                triggerDict["latitude"] = geo.coordinate.latitude
                triggerDict["longitude"] = geo.coordinate.longitude
            }
            if structured.radius > 0 { triggerDict["radius"] = structured.radius }
            switch alarm.proximity {
            case .enter: triggerDict["proximity"] = "enter"
            case .leave: triggerDict["proximity"] = "leave"
            default: break
            }
            return triggerDict
        }
        return nil
    }
}
