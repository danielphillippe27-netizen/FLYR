import XCTest
@testable import WolfGrid

final class CampaignMapModeResolutionTests: XCTestCase {
    func testExplicitMapModeWins() {
        XCTAssertEqual(
            CampaignMapMode.resolved(
                explicit: .hybrid,
                hasParcels: false,
                buildingLinkConfidence: 12
            ),
            .hybrid
        )
    }

    func testMissingConfigurationFallsBackToHybrid() {
        XCTAssertEqual(
            CampaignMapMode.resolved(
                explicit: nil,
                hasParcels: nil,
                buildingLinkConfidence: nil
            ),
            .hybrid
        )
    }

    func testNoParcelsAndLowConfidenceStillUsesHybrid() {
        XCTAssertEqual(
            CampaignMapMode.resolved(
                explicit: nil,
                hasParcels: false,
                buildingLinkConfidence: 45
            ),
            .hybrid
        )
    }

    func testParcelsWithModerateConfidenceUsesHybrid() {
        XCTAssertEqual(
            CampaignMapMode.resolved(
                explicit: nil,
                hasParcels: true,
                buildingLinkConfidence: 72
            ),
            .hybrid
        )
    }

    func testPresentationResolutionUsesHybrid() {
        XCTAssertEqual(
            CampaignMapMode.resolvedForPresentation(
                explicit: .hybrid,
                hasParcels: false,
                buildingLinkConfidence: 0,
                provisionPhase: .mapReady
            ),
            .hybrid
        )
    }

    func testCampaignPresentationMapModeUsesHybrid() {
        let campaign = CampaignV2(
            name: "Test Campaign",
            type: .flyer,
            addressSource: .map,
            provisionPhase: .optimized,
            hasParcels: false,
            buildingLinkConfidence: 45,
            mapMode: .hybrid
        )

        XCTAssertEqual(campaign.presentationMapMode, .hybrid)
    }
}
