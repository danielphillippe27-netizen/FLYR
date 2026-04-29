import XCTest
@testable import FLYR

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

    func testMissingConfigurationFallsBackToStandardPins() {
        XCTAssertEqual(
            CampaignMapMode.resolved(
                explicit: nil,
                hasParcels: nil,
                buildingLinkConfidence: nil
            ),
            .standardPins
        )
    }

    func testNoParcelsAndLowConfidenceUsesStandardPins() {
        XCTAssertEqual(
            CampaignMapMode.resolved(
                explicit: nil,
                hasParcels: false,
                buildingLinkConfidence: 45
            ),
            .standardPins
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

    func testPresentationResolutionCoercesStandardPinsToHybrid() {
        XCTAssertEqual(
            CampaignMapMode.resolvedForPresentation(
                explicit: .standardPins,
                hasParcels: false,
                buildingLinkConfidence: 0,
                provisionPhase: .mapReady
            ),
            .hybrid
        )
    }

    func testCampaignPresentationMapModeCoercesStandardPinsToHybrid() {
        let campaign = CampaignV2(
            name: "Test Campaign",
            type: .flyer,
            addressSource: .map,
            provisionPhase: .optimized,
            hasParcels: false,
            buildingLinkConfidence: 45,
            mapMode: .standardPins
        )

        XCTAssertEqual(campaign.presentationMapMode, .hybrid)
    }
}
