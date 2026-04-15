import XCTest
@testable import FLYR

final class CRMLeadEnrichmentTests: XCTestCase {
    func testAddressOnlyGetsSyntheticEmailAndPropertyName() {
        let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
        let lead = LeadModel(
            id: id,
            name: nil,
            phone: nil,
            email: nil,
            address: "88 River Rd",
            source: "Field Lead",
            campaignId: nil,
            notes: nil,
            createdAt: Date()
        )
        XCTAssertTrue(lead.isValidLead)
        let enriched = CRMLeadEnrichment.enrichedForSecureProviders(lead)
        XCTAssertTrue(enriched.email?.contains("@capture.flyrpro.app") == true)
        XCTAssertTrue(enriched.name?.hasPrefix("Property:") == true)
    }

    func testPhoneOnlyGetsDisplayNameForHubSpot() {
        let lead = LeadModel(
            name: nil,
            phone: "+15551234567",
            email: nil,
            address: nil,
            source: "Field Lead",
            campaignId: nil,
            notes: nil,
            createdAt: Date()
        )
        let enriched = CRMLeadEnrichment.enrichedForSecureProviders(lead)
        XCTAssertEqual(enriched.phone, "+15551234567")
        XCTAssertFalse((enriched.name ?? "").isEmpty)
    }

    func testRichLeadUnchanged() {
        let lead = LeadModel(
            name: "Ada Lovelace",
            phone: nil,
            email: "ada@example.com",
            address: "123 St",
            source: "Field Lead",
            campaignId: nil,
            notes: nil,
            createdAt: Date()
        )
        let enriched = CRMLeadEnrichment.enrichedForSecureProviders(lead)
        XCTAssertEqual(enriched.email, "ada@example.com")
        XCTAssertEqual(enriched.name, "Ada Lovelace")
    }
}
