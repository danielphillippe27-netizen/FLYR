import XCTest
@testable import WolfGrid

final class LocationCardSaveOutcomePolicyTests: XCTestCase {
    func testPrimaryActionOrderAndImmediateStatuses() {
        XCTAssertEqual(
            LocationCardPrimaryAction.allCases.map { String(describing: $0) },
            ["noAnswer", "talked", "lead", "notes", "tools"]
        )
        XCTAssertEqual(LocationCardPrimaryAction.noAnswer.immediateStatus, .noAnswer)
        XCTAssertEqual(LocationCardPrimaryAction.talked.immediateStatus, .talked)
        XCTAssertNil(LocationCardPrimaryAction.lead.immediateStatus)
        XCTAssertNil(LocationCardPrimaryAction.notes.immediateStatus)
        XCTAssertNil(LocationCardPrimaryAction.tools.immediateStatus)
    }

    func testContactDetailsCreateBlueLeadOutcome() {
        XCTAssertEqual(
            LocationCardSaveOutcomePolicy.resolvedStatus(
                hasContactDetails: true,
                hasNotes: false,
                scheduledStatus: nil,
                suggestedStatus: nil
            ),
            .hotLead
        )
    }

    func testNotesCreateBlueLeadOutcome() {
        XCTAssertEqual(
            LocationCardSaveOutcomePolicy.resolvedStatus(
                hasContactDetails: false,
                hasNotes: true,
                scheduledStatus: nil,
                suggestedStatus: nil
            ),
            .hotLead
        )
    }

    func testEmptyEditorDoesNotCreateOutcome() {
        XCTAssertNil(
            LocationCardSaveOutcomePolicy.resolvedStatus(
                hasContactDetails: false,
                hasNotes: false,
                scheduledStatus: nil,
                suggestedStatus: nil
            )
        )
    }

    func testScheduledOutcomeTakesPriorityOverLeadContent() {
        XCTAssertEqual(
            LocationCardSaveOutcomePolicy.resolvedStatus(
                hasContactDetails: true,
                hasNotes: true,
                scheduledStatus: .appointment,
                suggestedStatus: .talked
            ),
            .appointment
        )
        XCTAssertEqual(
            LocationCardSaveOutcomePolicy.resolvedStatus(
                hasContactDetails: true,
                hasNotes: true,
                scheduledStatus: .futureSeller,
                suggestedStatus: nil
            ),
            .futureSeller
        )
    }

    func testStructuredVoiceOutcomeIsPreserved() {
        XCTAssertEqual(
            LocationCardSaveOutcomePolicy.resolvedStatus(
                hasContactDetails: false,
                hasNotes: true,
                scheduledStatus: nil,
                suggestedStatus: .noAnswer
            ),
            .noAnswer
        )
    }
}
