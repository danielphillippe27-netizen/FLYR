import XCTest
@testable import WolfGrid

final class BusinessCardDeliveryTests: XCTestCase {
    private func share(_ types: [String], revoked: Bool = false) -> BusinessCardActivityResponse.Share {
        .init(id: UUID(), created_at: "2026-09-18T21:00:00Z", revoked_at: revoked ? "2026-09-18T22:00:00Z" : nil,
              card_events: types.map { .init(id: UUID(), event_type: $0, detail: nil, created_at: "2026-09-18T21:02:00.123Z") })
    }
    func testCreatingOpeningOrCancellingComposerDoesNotMeanSent() {
        for events in [[], ["composer_opened"], ["composer_cancelled"], ["composer_failed"]] as [[String]] {
            let status = BusinessCardDeliveryStatus(shares: [share(events)])
            XCTAssertFalse(status.sent)
            XCTAssertNil(status.lastOpen)
        }
        XCTAssertTrue(BusinessCardDeliveryStatus(shares: [share(["composer_sent"])]).sent)
    }
    func testQualifiedOpenAndRecipientInteractionsIgnoreComposerAndRevokedLinks() {
        let status = BusinessCardDeliveryStatus(shares: [
            share(["composer_opened", "composer_sent", "qualified_open", "call_clicked", "social_clicked"]),
            share(["qualified_open", "email_clicked"], revoked: true)
        ])
        XCTAssertNotNil(status.lastOpen)
        XCTAssertEqual(status.interactionCount, 2)
        XCTAssertTrue(status.sent)
    }
    func testValidContactChannels() {
        XCTAssertTrue(BusinessCardRecipient.validPhone("(289) 555-1234"))
        XCTAssertFalse(BusinessCardRecipient.validPhone("abcdefg1234567"))
        XCTAssertFalse(BusinessCardRecipient.validPhone("123"))
        XCTAssertFalse(BusinessCardRecipient.validPhone("1234567890123456"))
        XCTAssertTrue(BusinessCardRecipient.validEmail(" person@example.com "))
        XCTAssertFalse(BusinessCardRecipient.validEmail("person@"))
        XCTAssertFalse(BusinessCardRecipient.validEmail(""))
    }
}
