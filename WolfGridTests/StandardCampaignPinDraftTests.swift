import Foundation
#if !WOLFGRID_STANDALONE_MAP_TESTS
import XCTest
@testable import WolfGrid
#endif

final class StandardCampaignPinDraftTests: XCTestCase {
    func testImmediateStatusWaitsForMatchingPersistedAddress() {
        var draft = StandardCampaignPinDraft<String>()
        let id = UUID()
        draft.begin(addressID: id)
        XCTAssertTrue(draft.queue("talked", addressID: id))
        XCTAssertEqual(draft.pendingAction, "talked")
        XCTAssertNil(draft.finish(addressID: UUID()))
        XCTAssertEqual(draft.pendingAction, "talked")
        XCTAssertEqual(draft.finish(addressID: id), "talked")
        XCTAssertNil(draft.finish(addressID: id))
        XCTAssertNil(draft.addressID)
    }

    func testDismissalAndFailedSaveDoNotReplayAChoice() {
        for action in ["no_answer", "talked", "hot_lead", "future_seller", "appointment"] {
            var draft = StandardCampaignPinDraft<String>()
            let id = UUID()
            draft.begin(addressID: id)
            XCTAssertTrue(draft.queue(action, addressID: id))
            draft.cancel()
            XCTAssertNil(draft.finish(addressID: id))
            XCTAssertNil(draft.pendingAction)
            XCTAssertEqual(draft.queue(action, addressID: id), false)
        }
    }

    func testOldPinCompletionCannotConsumeNewPinChoice() {
        var draft = StandardCampaignPinDraft<String>()
        let old = UUID(), next = UUID()
        draft.begin(addressID: old)
        XCTAssertTrue(draft.queue("talked", addressID: old))
        draft.begin(addressID: next)
        XCTAssertNil(draft.pendingAction)
        XCTAssertTrue(draft.queue("appointment", addressID: next))
        XCTAssertNil(draft.finish(addressID: old))
        XCTAssertEqual(draft.finish(addressID: next), "appointment")
    }

    func testEveryStatusCanBeChosenBeforeLocalWriteCompletes() {
        for action in ["no_answer", "talked", "hot_lead", "future_seller", "appointment"] {
            var draft = StandardCampaignPinDraft<String>()
            let id = UUID()
            draft.begin(addressID: id)
            XCTAssertTrue(draft.queue(action, addressID: id))
            XCTAssertEqual(draft.finish(addressID: id), action)
        }
    }

    static var standaloneTests: [(String, (StandardCampaignPinDraftTests) -> () throws -> Void)] {
        [
            ("choice waits for matching pin", testImmediateStatusWaitsForMatchingPersistedAddress),
            ("dismiss and failure discard choice", testDismissalAndFailedSaveDoNotReplayAChoice),
            ("stale completion cannot change next pin", testOldPinCompletionCannotConsumeNewPinChoice),
            ("all five statuses before persistence", testEveryStatusCanBeChosenBeforeLocalWriteCompletes)
        ]
    }
}
