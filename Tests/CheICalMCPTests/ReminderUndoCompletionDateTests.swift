import Foundation
import XCTest
@testable import CheICalMCP

final class ReminderUndoCompletionDateTests: XCTestCase {
    func testCompleteReminderUndoOperationCarriesOldAndNewCompletionDates() {
        let oldDate = Date(timeIntervalSince1970: 1_778_400_000)
        let newDate = Date(timeIntervalSince1970: 1_778_407_200)

        let operation = UndoOperation.completeReminder(
            id: "reminder-1",
            wasCompleted: true,
            previousCompletionDate: oldDate,
            newCompleted: true,
            newCompletionDate: newDate,
            title: "Restored task"
        )

        guard case .completeReminder(
            let id,
            let wasCompleted,
            let previousCompletionDate,
            let newCompleted,
            let newCompletionDate,
            let title
        ) = operation else {
            return XCTFail("expected completeReminder operation")
        }

        XCTAssertEqual(id, "reminder-1")
        XCTAssertTrue(wasCompleted)
        XCTAssertEqual(previousCompletionDate, oldDate)
        XCTAssertTrue(newCompleted)
        XCTAssertEqual(newCompletionDate, newDate)
        XCTAssertEqual(title, "Restored task")
    }
}
