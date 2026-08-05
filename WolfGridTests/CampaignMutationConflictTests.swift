import XCTest
@testable import WolfGrid

final class CampaignMutationConflictTests: XCTestCase {
    private let campaignId = "22222222-2222-2222-2222-222222222222"
    private let addressId = "33333333-3333-3333-3333-333333333333"

    func testConsecutiveOfflineStatusWritesAdvanceTheirRevisionChain() {
        let firstBase = CampaignStatusRevisionChain.baseRevision(from: nil)
        let firstOptimisticRevision = CampaignStatusRevisionChain.optimisticRevision(after: firstBase)
        let secondBase = CampaignStatusRevisionChain.baseRevision(from: firstOptimisticRevision)
        let secondOptimisticRevision = CampaignStatusRevisionChain.optimisticRevision(after: secondBase)

        XCTAssertEqual(firstBase, 0)
        XCTAssertEqual(firstOptimisticRevision, 1)
        XCTAssertEqual(secondBase, 1)
        XCTAssertEqual(secondOptimisticRevision, 2)
    }

    func testConflictAttributionRecognizesCurrentUserInsteadOfTeammate() throws {
        let currentUserId = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let payload = AddressStatusOutboxPayload(
            campaignId: campaignId,
            addressIds: [addressId],
            buildingId: nil,
            status: "talked",
            notes: nil,
            sessionId: nil,
            sessionTargetId: nil,
            sessionEventType: nil,
            latitude: nil,
            longitude: nil,
            occurredAt: "2026-07-16T10:00:00Z",
            farmExecutionContext: nil,
            baseRevisions: [addressId: 0],
            overrideReason: nil
        )
        let canonicalState = "{\"revision\":1,\"last_action_by\":\"\(currentUserId.uuidString)\"}"
        let entry = OutboxEntry(
            id: "self-conflict",
            clientMutationId: "self-conflict-mutation",
            entityType: "address_status",
            entityId: addressId,
            operation: OutboxOperation.upsertAddressStatus.rawValue,
            operationVersion: 1,
            payloadJSON: try XCTUnwrap(OfflineJSONCodec.encode(payload)),
            status: "conflict",
            dependencyKey: "address_status:\(campaignId):\(addressId)",
            createdAt: "2026-07-16T10:00:00Z",
            attemptedAt: nil,
            syncedAt: nil,
            retryAfter: nil,
            retryCount: 1,
            errorMessage: "REVISION_CONFLICT|\(canonicalState)",
            deadLetteredAt: nil
        )

        let conflict = try XCTUnwrap(CampaignMutationConflictResolver.conflict(from: entry))
        XCTAssertEqual(conflict.canonicalActorUserId, currentUserId)
        XCTAssertEqual(conflict.attribution(for: currentUserId), .currentUser)
    }

    func testOfflinePinConflictRetainsDraftAndReadsCanonicalRevision() throws {
        let entry = try makeMoveConflictEntry(baseRevision: 1, canonicalRevision: 2)

        let conflict = try XCTUnwrap(CampaignMutationConflictResolver.conflict(from: entry))
        XCTAssertEqual(conflict.campaignId, campaignId)
        XCTAssertEqual(conflict.operation, .moveAddress)
        XCTAssertEqual(conflict.canonicalRevision, 2)

        let retainedDraft = try XCTUnwrap(
            OfflineJSONCodec.decode(MoveAddressOutboxPayload.self, from: conflict.draftPayloadJSON)
        )
        XCTAssertEqual(retainedDraft.baseRevision, 1)
        XCTAssertEqual(retainedDraft.latitude, 43.6512, accuracy: 0.000_001)
        XCTAssertEqual(retainedDraft.longitude, -79.3812, accuracy: 0.000_001)
    }

    func testExplicitReapplyUsesNewMutationIDAndLatestRevisionWithoutChangingDraft() throws {
        let entry = try makeMoveConflictEntry(baseRevision: 1, canonicalRevision: 2)
        let newMutationId = "reapply-mutation-2"

        let plan = try XCTUnwrap(
            CampaignMutationConflictResolver.reapplyPlan(
                for: entry,
                newClientMutationId: newMutationId
            )
        )
        XCTAssertEqual(plan.clientMutationId, newMutationId)
        XCTAssertNotEqual(plan.clientMutationId, entry.clientMutationId)
        XCTAssertEqual(plan.baseRevision, 2)

        let rebasedDraft = try XCTUnwrap(
            OfflineJSONCodec.decode(MoveAddressOutboxPayload.self, from: plan.payloadJSON)
        )
        XCTAssertEqual(rebasedDraft.baseRevision, 2)
        XCTAssertEqual(rebasedDraft.latitude, 43.6512, accuracy: 0.000_001)
        XCTAssertEqual(rebasedDraft.longitude, -79.3812, accuracy: 0.000_001)
    }

    func testStatusReapplyRebasesEveryAddressAtomically() throws {
        let secondAddressId = "44444444-4444-4444-4444-444444444444"
        let payload = AddressStatusOutboxPayload(
            campaignId: campaignId,
            addressIds: [addressId, secondAddressId],
            buildingId: nil,
            status: "talked",
            notes: "offline draft",
            sessionId: nil,
            sessionTargetId: nil,
            sessionEventType: nil,
            latitude: nil,
            longitude: nil,
            occurredAt: "2026-07-16T10:00:00Z",
            farmExecutionContext: nil,
            baseRevisions: [addressId: 1, secondAddressId: 1],
            overrideReason: nil
        )
        let entry = try makeEntry(
            operation: .upsertAddressStatus,
            payloadJSON: XCTUnwrap(OfflineJSONCodec.encode(payload)),
            canonicalRevision: 4
        )

        let plan = try XCTUnwrap(
            CampaignMutationConflictResolver.reapplyPlan(
                for: entry,
                newClientMutationId: "status-reapply"
            )
        )
        let rebased = try XCTUnwrap(
            OfflineJSONCodec.decode(AddressStatusOutboxPayload.self, from: plan.payloadJSON)
        )
        XCTAssertEqual(rebased.baseRevisions?[addressId], 4)
        XCTAssertEqual(rebased.baseRevisions?[secondAddressId], 4)
        XCTAssertEqual(rebased.status, "talked")
        XCTAssertEqual(rebased.notes, "offline draft")
    }

    func testMalformedCanonicalStateCannotSilentlyReapply() throws {
        let payload = MoveAddressOutboxPayload(
            campaignId: campaignId,
            addressId: addressId,
            latitude: 43.6512,
            longitude: -79.3812,
            baseRevision: 1,
            occurredAt: "2026-07-16T10:00:00Z"
        )
        let entry = OutboxEntry(
            id: "outbox-malformed",
            clientMutationId: "offline-mutation-1",
            entityType: "address",
            entityId: "\(campaignId):\(addressId)",
            operation: OutboxOperation.moveAddress.rawValue,
            operationVersion: 1,
            payloadJSON: try XCTUnwrap(OfflineJSONCodec.encode(payload)),
            status: "conflict",
            dependencyKey: "address:\(campaignId):\(addressId)",
            createdAt: "2026-07-16T10:00:00Z",
            attemptedAt: nil,
            syncedAt: nil,
            retryAfter: nil,
            retryCount: 1,
            errorMessage: "REVISION_CONFLICT|not-json",
            deadLetteredAt: nil
        )

        XCTAssertNil(CampaignMutationConflictResolver.reapplyPlan(for: entry))
    }

    private func makeMoveConflictEntry(baseRevision: Int, canonicalRevision: Int) throws -> OutboxEntry {
        let payload = MoveAddressOutboxPayload(
            campaignId: campaignId,
            addressId: addressId,
            latitude: 43.6512,
            longitude: -79.3812,
            baseRevision: baseRevision,
            occurredAt: "2026-07-16T10:00:00Z"
        )
        return try makeEntry(
            operation: .moveAddress,
            payloadJSON: XCTUnwrap(OfflineJSONCodec.encode(payload)),
            canonicalRevision: canonicalRevision
        )
    }

    private func makeEntry(
        operation: OutboxOperation,
        payloadJSON: String,
        canonicalRevision: Int
    ) throws -> OutboxEntry {
        let canonicalState = """
        {"id":"\(addressId)","revision":\(canonicalRevision),"formatted":"Server version"}
        """
        return OutboxEntry(
            id: "outbox-1",
            clientMutationId: "offline-mutation-1",
            entityType: "address",
            entityId: "\(campaignId):\(addressId)",
            operation: operation.rawValue,
            operationVersion: 1,
            payloadJSON: payloadJSON,
            status: "conflict",
            dependencyKey: "address:\(campaignId):\(addressId)",
            createdAt: "2026-07-16T10:00:00Z",
            attemptedAt: "2026-07-16T10:05:00Z",
            syncedAt: nil,
            retryAfter: nil,
            retryCount: 1,
            errorMessage: "REVISION_CONFLICT|\(canonicalState)",
            deadLetteredAt: nil
        )
    }
}
