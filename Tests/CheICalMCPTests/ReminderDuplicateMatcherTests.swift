import Foundation
import XCTest
@testable import CheICalMCP

final class ReminderDuplicateMatcherTests: XCTestCase {
    func testCompletedReminderRequiresMatchingCompletionDate() {
        let dueDate = Date(timeIntervalSince1970: 1_778_400_000)
        let completionDate = Date(timeIntervalSince1970: 1_778_407_200)

        XCTAssertTrue(EventKitManager.reminderDuplicateMatches(
            existingTitle: "Archive invoice",
            existingDueDate: dueDate,
            existingCompletionDate: completionDate,
            requestedTitle: "Archive invoice",
            requestedDueDate: dueDate,
            requestedCompletionDate: completionDate
        ))

        XCTAssertFalse(EventKitManager.reminderDuplicateMatches(
            existingTitle: "Archive invoice",
            existingDueDate: dueDate,
            existingCompletionDate: completionDate.addingTimeInterval(120),
            requestedTitle: "Archive invoice",
            requestedDueDate: dueDate,
            requestedCompletionDate: completionDate
        ))

        XCTAssertTrue(EventKitManager.reminderDuplicateMatches(
            existingTitle: "Archive invoice",
            existingDueDate: nil,
            existingCompletionDate: completionDate,
            requestedTitle: "Archive invoice",
            requestedDueDate: nil,
            requestedCompletionDate: completionDate
        ))
    }

    func testIncompleteReminderStillMatchesByTitleAndDueDate() {
        let dueDate = Date(timeIntervalSince1970: 1_778_400_000)

        XCTAssertTrue(EventKitManager.reminderDuplicateMatches(
            existingTitle: "Pay bill",
            existingDueDate: dueDate,
            existingCompletionDate: nil,
            requestedTitle: "Pay bill",
            requestedDueDate: dueDate,
            requestedCompletionDate: nil
        ))
    }
}
