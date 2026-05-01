import XCTest
@testable import FLYR

final class CampaignLinkerQualityContractTests: XCTestCase {
    func testProvisionResponseDecodesCampaignLevelQualityGrade() throws {
        let data = """
        {
          "success": true,
          "coverage_score": 92,
          "data_quality": "strong",
          "standard_mode_recommended": false,
          "reason": "low building-address confidence",
          "building_link_confidence": 91.5,
          "map_mode": "smart_buildings",
          "provision_status": "ready",
          "provision_phase": "optimized"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CampaignProvisionResponse.self, from: data)

        XCTAssertEqual(decoded.coverageScore, 92)
        XCTAssertEqual(decoded.dataQuality, .strong)
        XCTAssertEqual(decoded.standardModeRecommended, false)
        XCTAssertEqual(decoded.dataQualityReason, "low building-address confidence")
        XCTAssertEqual(decoded.buildingLinkConfidence, 91.5)
        XCTAssertEqual(decoded.mapMode, .smartBuildings)
    }

    func testCampaignRowCarriesQualityGradeIntoCampaignModel() throws {
        let rowData = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Quality Campaign",
          "description": null,
          "type": "flyer",
          "address_source": "map",
          "scans": 0,
          "conversions": 0,
          "region": "Toronto",
          "tags": null,
          "status": "draft",
          "provision_status": "ready",
          "provision_source": "gold",
          "provision_phase": "optimized",
          "addresses_ready_at": null,
          "map_ready_at": null,
          "optimized_at": null,
          "has_parcels": true,
          "building_link_confidence": 72,
          "map_mode": "hybrid",
          "coverage_score": 58,
          "data_quality": "weak",
          "standard_mode_recommended": true,
          "data_quality_reason": "low building-address confidence",
          "data_confidence_score": null,
          "data_confidence_label": null,
          "data_confidence_reason": null,
          "data_confidence_summary": null,
          "data_confidence_updated_at": null,
          "created_at": "2026-04-30T16:00:00.000Z",
          "updated_at": "2026-04-30T16:00:00.000Z",
          "owner_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8)!

        let row = try JSONDecoder.supabaseDates.decode(CampaignDBRow.self, from: rowData)
        let campaign = CampaignV2(
            id: row.id,
            name: row.title,
            type: row.campaignType,
            addressSource: row.addressSource,
            createdAt: row.createdAt,
            status: row.status ?? .draft,
            seedQuery: row.region,
            dataConfidence: row.dataConfidence,
            provisionStatus: row.provisionStatus,
            provisionSource: row.provisionSource,
            provisionPhase: row.provisionPhase,
            addressesReadyAt: row.addressesReadyAt,
            mapReadyAt: row.mapReadyAt,
            optimizedAt: row.optimizedAt,
            hasParcels: row.hasParcels,
            buildingLinkConfidence: row.buildingLinkConfidence,
            mapMode: row.mapMode,
            coverageScore: row.coverageScore,
            dataQuality: row.dataQuality,
            standardModeRecommended: row.standardModeRecommended,
            dataQualityReason: row.dataQualityReason
        )

        XCTAssertEqual(campaign.coverageScore, 58)
        XCTAssertEqual(campaign.dataQuality, .weak)
        XCTAssertEqual(campaign.standardModeRecommended, true)
        XCTAssertEqual(campaign.dataQualityReason, "low building-address confidence")
        XCTAssertEqual(campaign.presentationMapMode, .hybrid)
    }
}
