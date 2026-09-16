import XCTest
@testable import WolfGrid

final class CampaignMapModeResolutionTests: XCTestCase {
    func testStandardAlwaysUsesGoogleBeforeAndDuringSessions() {
        for dataResolved in [false, true] {
            for hasBuildings in [false, true] {
                for activeSession in [false, true] {
                    XCTAssertEqual(CampaignMapRendererDecision.resolve(
                        dataResolved: dataResolved,
                        hasRenderableBuildings: hasBuildings,
                        activeSession: activeSession,
                        sessionUses2D: false,
                        mapboxAvailable: true,
                        googleAvailable: true,
                        standardMode: true
                    ), .google2D)
                }
            }
        }
    }

    func testStandardWithoutGoogleDoesNotFallBackToMapbox() {
        XCTAssertNil(CampaignMapRendererDecision.resolve(
            dataResolved: false,
            hasRenderableBuildings: true,
            activeSession: true,
            sessionUses2D: false,
            mapboxAvailable: true,
            googleAvailable: false,
            standardMode: true
        ))
    }

    func testCampaignRendererWaitsForResolvedBuildingData() {
        XCTAssertNil(CampaignMapRendererDecision.resolve(
            dataResolved: false,
            hasRenderableBuildings: false,
            activeSession: false,
            sessionUses2D: false,
            mapboxAvailable: true,
            googleAvailable: true
        ))
    }

    func testCampaignRendererUsesBuildingAvailabilityOutsideSessions() {
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: true,
            hasRenderableBuildings: false,
            activeSession: false,
            sessionUses2D: false,
            mapboxAvailable: true,
            googleAvailable: true
        ), .google2D)
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: true,
            hasRenderableBuildings: true,
            activeSession: false,
            sessionUses2D: false,
            mapboxAvailable: true,
            googleAvailable: true
        ), .mapbox3D)
    }

    func testActiveSessionDefaultsTo3DAndHonors2DOverride() {
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: true,
            hasRenderableBuildings: false,
            activeSession: true,
            sessionUses2D: false,
            mapboxAvailable: true,
            googleAvailable: true
        ), .mapbox3D)
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: true,
            hasRenderableBuildings: true,
            activeSession: true,
            sessionUses2D: true,
            mapboxAvailable: true,
            googleAvailable: true
        ), .google2D)
    }

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
