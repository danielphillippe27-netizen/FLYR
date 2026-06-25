import XCTest
@testable import FLYR

final class OnboardingDemoTests: XCTestCase {
    func testDemoStateDecodesSnakeCasePayload() throws {
        let campaignId = UUID()
        let json = """
        {
          "workspace_id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "role_path": "solo_owner",
          "seeded_campaign_id": "\(campaignId.uuidString)",
          "dismissed_at": "2026-06-13T14:30:00Z",
          "completed_checklist_items": ["open_starter_campaign"],
          "has_assigned_work": false,
          "can_seed": true,
          "seed_skipped_reason": null
        }
        """

        let state = try JSONDecoder().decode(OnboardingDemoState.self, from: Data(json.utf8))

        XCTAssertEqual(state.rolePath, .soloOwner)
        XCTAssertEqual(state.seededCampaignId, campaignId)
        XCTAssertTrue(state.isDismissed)
        XCTAssertEqual(state.completedChecklistItems, ["open_starter_campaign"])
        XCTAssertTrue(state.canSeed)
    }

    func testDemoSeedResponseDecodesCamelCaseCampaignId() throws {
        let campaignId = UUID()
        let json = """
        {
          "seeded": true,
          "skipped": false,
          "campaignId": "\(campaignId.uuidString)",
          "state": {
            "rolePath": "team_owner",
            "seededCampaignId": "\(campaignId.uuidString)",
            "completedChecklistItems": [],
            "hasAssignedWork": true,
            "canSeed": true
          }
        }
        """

        let response = try JSONDecoder().decode(OnboardingDemoSeedResponse.self, from: Data(json.utf8))

        XCTAssertTrue(response.seeded)
        XCTAssertFalse(response.skipped)
        XCTAssertEqual(response.campaignId, campaignId)
        XCTAssertEqual(response.state.rolePath, .teamOwner)
        XCTAssertEqual(response.state.seededCampaignId, campaignId)
    }

    func testOwnerChecklistUsesStarterOrRecoveryAction() {
        let seededState = makeState(rolePath: .teamOwner, seededCampaignId: UUID())
        let seededItems = OnboardingDemoChecklistItem.items(for: seededState)

        XCTAssertEqual(seededItems.first?.id, "open_starter_campaign")
        XCTAssertTrue(seededItems.contains { $0.id == "assign_work" })
        XCTAssertTrue(seededItems.contains { $0.id == "view_team_stats" })

        let recoveryState = makeState(rolePath: .soloOwner, seededCampaignId: nil, seedSkippedReason: "workspace_has_campaigns")
        let recoveryItems = OnboardingDemoChecklistItem.items(for: recoveryState)

        XCTAssertEqual(recoveryItems.first?.id, "create_starter_campaign")
        XCTAssertFalse(recoveryItems.contains { $0.id == "assign_work" })
        XCTAssertTrue(recoveryItems.contains { $0.id == "create_real_campaign" })
    }

    func testMemberChecklistAvoidsOwnerCampaignCreationPrompts() {
        let memberState = makeState(rolePath: .member, seededCampaignId: nil, hasAssignedWork: false)

        let items = OnboardingDemoChecklistItem.items(for: memberState)

        XCTAssertEqual(items.first?.id, "open_assigned_work")
        XCTAssertFalse(items.contains { $0.id == "create_starter_campaign" })
        XCTAssertFalse(items.contains { $0.id == "create_real_campaign" })
        XCTAssertTrue(items.contains { $0.id == "record_outcomes" })
    }

    private func makeState(
        rolePath: OnboardingDemoRolePath,
        seededCampaignId: UUID?,
        hasAssignedWork: Bool = false,
        seedSkippedReason: String? = nil
    ) -> OnboardingDemoState {
        OnboardingDemoState(
            workspaceId: UUID(),
            userId: UUID(),
            rolePath: rolePath,
            seededCampaignId: seededCampaignId,
            dismissedAt: nil,
            completedChecklistItems: [],
            hasAssignedWork: hasAssignedWork,
            canSeed: rolePath.isOwnerPath,
            seedSkippedReason: seedSkippedReason
        )
    }
}
