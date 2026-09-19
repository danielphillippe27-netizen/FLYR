import Foundation
import XCTest
@testable import WolfGrid

@MainActor final class BusinessCardAutosaveTests: XCTestCase {
    func testAutosaveSerializationRecoveryAndPartialLinks() async throws {
        let suite = "card-autosave-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var initial = BusinessCardContent(); initial.name = "Daniel"
        let remote = BusinessCardDraft(card: initial, published: false)
        var writes: [BusinessCardDraft] = []
        var release: CheckedContinuation<Void, Never>?
        var wasCancelled = false
        let store = BusinessCardEditorStore(key: "one", defaults: defaults, delay: 10_000_000, read: { remote }, write: { draft in
            writes.append(draft)
            if writes.count == 1 { await withCheckedContinuation { release = $0 } }
            wasCancelled = wasCancelled || Task.isCancelled
        })
        await store.load()
        XCTAssertTrue(writes.isEmpty)
        store.card.company = "First"
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(writes.count == 1)
        store.card.company = "Latest"
        store.card.photo = "https://example.com/photo.jpg"
        XCTAssertTrue(defaults.data(forKey: "one") != nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(writes.count == 1, "Concurrent save must not start")
        release?.resume()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(writes.count == 2 && writes.last?.card.company == "Latest")
        XCTAssertTrue(writes.last?.published == true && writes.last?.card.photo == "https://example.com/photo.jpg")
        XCTAssertTrue(!wasCancelled, "Editing must not cancel an in-flight write")
        XCTAssertTrue(defaults.data(forKey: "one") == nil)
        var fail = true
        let failing = BusinessCardEditorStore(key: "offline", defaults: defaults, delay: 1_000_000, read: { remote }, write: { _ in
            if fail { throw NSError(domain: "offline", code: 1) }
        })
        await failing.load()
        failing.card.bio = "Keep this text"
        failing.flush()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(failing.canRetry && defaults.data(forKey: "offline") != nil)
        let restored = BusinessCardEditorStore(key: "offline", defaults: defaults, delay: 1_000_000, read: { throw NSError(domain: "offline", code: 1) }, write: { _ in })
        await restored.load()
        XCTAssertTrue(restored.loaded && restored.card.bio == "Keep this text")
        fail = false
        failing.flush()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(!failing.canRetry && defaults.data(forKey: "offline") == nil)
        store.card.reviewUrl = "https://"
        store.flush()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(writes.count == 2 && defaults.data(forKey: "one") != nil)
        store.card.reviewUrl = "https://example.com/review"
        store.flush()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(writes.count == 3 && defaults.data(forKey: "one") == nil)
    }
}
