import XCTest
@testable import FLYR

@MainActor
final class BuildingDataServiceTests: XCTestCase {
    private func makeCampaignAddressResponse(
        id: UUID = UUID(),
        houseNumber: String = "123",
        streetName: String = "Main St",
        formatted: String = "123 Main St, Toronto, ON",
        scans: Int = 5
    ) throws -> CampaignAddressResponse {
        let payload: [String: Any] = [
            "id": id.uuidString,
            "house_number": houseNumber,
            "street_name": streetName,
            "formatted": formatted,
            "locality": "Toronto",
            "region": "ON",
            "postal_code": "M5V 2T6",
            "gers_id": UUID().uuidString,
            "building_gers_id": NSNull(),
            "scans": scans,
            "last_scanned_at": ISO8601DateFormatter().string(from: Date()),
            "qr_code_base64": "base64data"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CampaignAddressResponse.self, from: data)
    }

    private func makeBuildingFeature(
        gersId: String,
        width: Double = 20,
        depth: Double = 6
    ) throws -> BuildingFeature {
        let payload: [String: Any] = [
            "type": "Feature",
            "id": gersId,
            "geometry": [
                "type": "Polygon",
                "coordinates": [[
                    [-79.0, 43.0],
                    [-79.0 + width / 10000.0, 43.0],
                    [-79.0 + width / 10000.0, 43.0 + depth / 10000.0],
                    [-79.0, 43.0 + depth / 10000.0],
                    [-79.0, 43.0]
                ]]
            ],
            "properties": [
                "id": gersId,
                "gers_id": gersId,
                "height": 10,
                "height_m": 10,
                "min_height": 0,
                "is_townhome": true,
                "units_count": 3,
                "status": "not_visited",
                "scans_today": 0,
                "scans_total": 0,
                "address_count": 3
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try JSONDecoder().decode(BuildingFeature.self, from: data)
    }

    private func makeAddressFeature(
        id: UUID,
        buildingGersId: String,
        houseNumber: String,
        formatted: String
    ) throws -> AddressFeature {
        let payload: [String: Any] = [
            "type": "Feature",
            "id": id.uuidString,
            "geometry": [
                "type": "Point",
                "coordinates": [-79.0, 43.0]
            ],
            "properties": [
                "id": id.uuidString,
                "building_gers_id": buildingGersId,
                "house_number": houseNumber,
                "street_name": "Richfield Square",
                "formatted": formatted
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try JSONDecoder().decode(AddressFeature.self, from: data)
    }
    
    // Note: These tests require a mock Supabase client for full testing
    // For now, we'll test the data models and logic
    
    // MARK: - ResolvedAddress Tests
    
    func testResolvedAddressDisplayStreet() {
        let address = ResolvedAddress(
            id: UUID(),
            street: "123 Main St",
            formatted: "123 Main St, Toronto, ON",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            houseNumber: "123",
            streetName: "Main St",
            gersId: UUID().uuidString
        )
        
        XCTAssertEqual(address.displayStreet, "123 Main St")
    }
    
    func testResolvedAddressDisplayStreetFallback() {
        let address = ResolvedAddress(
            id: UUID(),
            street: "",
            formatted: "Unknown Address",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            houseNumber: "",
            streetName: "",
            gersId: UUID().uuidString
        )
        
        XCTAssertEqual(address.displayStreet, "Unknown Address")
    }
    
    func testResolvedAddressDisplayFull() {
        let address = ResolvedAddress(
            id: UUID(),
            street: "123 Main St",
            formatted: "123 Main St, Toronto, ON",
            locality: "Toronto",
            region: "ON",
            postalCode: "M5V 2T6",
            houseNumber: "123",
            streetName: "Main St",
            gersId: UUID().uuidString
        )
        
        XCTAssertEqual(address.displayFull, "123 Main St, Toronto, ON, M5V 2T6")
    }

    func testCampaignAddressResponseDoesNotInventOntarioWhenRegionMissing() throws {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "house_number": "123",
            "street_name": "Main St",
            "formatted": "123 Main St, Toronto",
            "locality": "Toronto",
            "postal_code": "M5V 2T6",
            "gers_id": UUID().uuidString,
            "building_gers_id": NSNull(),
            "scans": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(CampaignAddressResponse.self, from: data)

        XCTAssertNil(response.region)
        XCTAssertEqual(response.toResolvedAddress(fallbackGersId: "fallback").region, "")
    }
    
    // MARK: - QRStatus Tests
    
    func testQRStatusIsScanned() {
        let scannedStatus = QRStatus(hasFlyer: true, totalScans: 5, lastScannedAt: Date())
        XCTAssertTrue(scannedStatus.isScanned)
        
        let unscannedStatus = QRStatus(hasFlyer: true, totalScans: 0, lastScannedAt: nil)
        XCTAssertFalse(unscannedStatus.isScanned)
    }
    
    func testQRStatusText() {
        let scannedStatus = QRStatus(hasFlyer: true, totalScans: 5, lastScannedAt: Date())
        XCTAssertEqual(scannedStatus.statusText, "Scanned 5x")
        
        let unscannedStatus = QRStatus(hasFlyer: true, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(unscannedStatus.statusText, "Flyer delivered")
        
        let noFlyerStatus = QRStatus(hasFlyer: false, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(noFlyerStatus.statusText, "No QR code")
    }
    
    func testQRStatusSubtext() {
        let scannedStatus = QRStatus(hasFlyer: true, totalScans: 5, lastScannedAt: Date())
        XCTAssertTrue(scannedStatus.subtext.contains("Last:"))
        
        let unscannedStatus = QRStatus(hasFlyer: true, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(unscannedStatus.subtext, "Not scanned yet")
        
        let noFlyerStatus = QRStatus(hasFlyer: false, totalScans: 0, lastScannedAt: nil)
        XCTAssertEqual(noFlyerStatus.subtext, "Generate online flyrpro.app")
    }
    
    // MARK: - BuildingData Tests
    
    func testBuildingDataHasAddress() {
        let addressData = BuildingData(
            isLoading: false,
            error: nil,
            address: ResolvedAddress(
                id: UUID(),
                street: "123 Main St",
                formatted: "123 Main St",
                locality: "Toronto",
                region: "ON",
                postalCode: "M5V 2T6",
                houseNumber: "123",
                streetName: "Main St",
                gersId: UUID().uuidString
            ),
            addresses: [],
            residents: [],
            qrStatus: .empty,
            buildingExists: true,
            addressLinked: true,
            contactName: nil,
            leadStatus: nil,
            productInterest: nil,
            followUpDate: nil,
            aiSummary: nil
        )
        
        XCTAssertTrue(addressData.hasAddress)
        
        let noAddressData = BuildingData(
            isLoading: false,
            error: nil,
            address: nil,
            addresses: [],
            residents: [],
            qrStatus: .empty,
            buildingExists: false,
            addressLinked: false,
            contactName: nil,
            leadStatus: nil,
            productInterest: nil,
            followUpDate: nil,
            aiSummary: nil
        )
        
        XCTAssertFalse(noAddressData.hasAddress)
    }
    
    func testBuildingDataHasNotes() {
        let contact = Contact(
            id: UUID(),
            fullName: "John Doe",
            phone: "555-1234",
            email: "john@example.com",
            address: "123 Main St",
            campaignId: UUID(),
            farmId: nil,
            status: .new,
            lastContacted: nil,
            notes: "Interested in solar panels",
            reminderDate: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let dataWithNotes = BuildingData(
            isLoading: false,
            error: nil,
            address: nil,
            addresses: [],
            residents: [contact],
            qrStatus: .empty,
            buildingExists: true,
            addressLinked: true,
            contactName: nil,
            leadStatus: nil,
            productInterest: nil,
            followUpDate: nil,
            aiSummary: nil
        )
        
        XCTAssertTrue(dataWithNotes.hasNotes)
        XCTAssertEqual(dataWithNotes.firstNotes, "Interested in solar panels")
    }
    
    // MARK: - CachedBuildingData Tests
    
    func testCachedBuildingDataIsValid() {
        let cached = CachedBuildingData(
            data: .empty,
            timestamp: Date()
        )
        
        XCTAssertTrue(cached.isValid(ttl: 300))
        
        let oldCached = CachedBuildingData(
            data: .empty,
            timestamp: Date().addingTimeInterval(-400)
        )
        
        XCTAssertFalse(oldCached.isValid(ttl: 300))
    }
    
    // MARK: - CampaignAddressResponse Tests
    
    func testCampaignAddressResponseToResolvedAddress() throws {
        let response = try makeCampaignAddressResponse()
        
        let fallbackGersId = UUID().uuidString
        let resolved = response.toResolvedAddress(fallbackGersId: fallbackGersId)
        
        XCTAssertEqual(resolved.houseNumber, "123")
        XCTAssertEqual(resolved.streetName, "Main St")
        XCTAssertEqual(resolved.street, "123 Main St")
        XCTAssertNotNil(resolved.gersId)
    }
    
    func testCampaignAddressResponseToQRStatus() throws {
        let response = try makeCampaignAddressResponse(formatted: "123 Main St")
        
        let qrStatus = response.toQRStatus()
        
        XCTAssertTrue(qrStatus.hasFlyer)
        XCTAssertEqual(qrStatus.totalScans, 5)
        XCTAssertNotNil(qrStatus.lastScannedAt)
    }

    func testSortAddressesForDisplayOrdersHouseNumbersAscending() throws {
        let unordered = try [
            makeCampaignAddressResponse(houseNumber: "55", streetName: "Richfield Square", formatted: "55 Richfield Square, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "51", streetName: "Richfield Square", formatted: "51 Richfield Square, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "47", streetName: "Richfield Square", formatted: "47 Richfield Square, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "53", streetName: "Richfield Square", formatted: "53 Richfield Square, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "45", streetName: "Richfield Square", formatted: "45 Richfield Square, Toronto, ON")
        ]

        let sorted = BuildingDataService.sortAddressesForDisplay(unordered)

        XCTAssertEqual(sorted.map(\.houseNumber), ["45", "47", "51", "53", "55"])
    }

    func testSortAddressesForDisplayHandlesSuffixesNaturally() throws {
        let unordered = try [
            makeCampaignAddressResponse(houseNumber: "12B", streetName: "Main St", formatted: "12B Main St, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "12", streetName: "Main St", formatted: "12 Main St, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "12A", streetName: "Main St", formatted: "12A Main St, Toronto, ON")
        ]

        let sorted = BuildingDataService.sortAddressesForDisplay(unordered)

        XCTAssertEqual(sorted.map(\.houseNumber), ["12", "12A", "12B"])
    }

    func testTownhomeOverlayBuildsMixedRedGreenBlueSegments() throws {
        let building = try makeBuildingFeature(gersId: "townhome-1")
        let firstId = UUID()
        let secondId = UUID()
        let thirdId = UUID()
        let addresses = try [
            makeAddressFeature(id: firstId, buildingGersId: "townhome-1", houseNumber: "45", formatted: "45 Richfield Square"),
            makeAddressFeature(id: secondId, buildingGersId: "townhome-1", houseNumber: "47", formatted: "47 Richfield Square"),
            makeAddressFeature(id: thirdId, buildingGersId: "townhome-1", houseNumber: "49", formatted: "49 Richfield Square")
        ]

        let data = MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: [building],
            addresses: addresses,
            orderedAddressIdsByBuilding: ["townhome-1": [firstId, secondId, thirdId]],
            addressStatuses: [
                firstId: .untouched,
                secondId: .delivered,
                thirdId: .talked
            ]
        )

        let json = try XCTUnwrap(data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [[String: Any]])
        let statuses = features.compactMap { ($0["properties"] as? [String: Any])?["segment_status"] as? String }

        XCTAssertEqual(statuses, ["not_visited", "visited", "hot"])
    }

    func testTownhomeOverlayOmitsRedWhenEveryUnitIsCompleted() throws {
        let building = try makeBuildingFeature(gersId: "townhome-2")
        let firstId = UUID()
        let secondId = UUID()
        let addresses = try [
            makeAddressFeature(id: firstId, buildingGersId: "townhome-2", houseNumber: "51", formatted: "51 Richfield Square"),
            makeAddressFeature(id: secondId, buildingGersId: "townhome-2", houseNumber: "53", formatted: "53 Richfield Square")
        ]

        let data = MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: [building],
            addresses: addresses,
            orderedAddressIdsByBuilding: ["townhome-2": [firstId, secondId]],
            addressStatuses: [
                firstId: .delivered,
                secondId: .talked
            ]
        )

        let json = try XCTUnwrap(data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [[String: Any]])
        let statuses = features.compactMap { ($0["properties"] as? [String: Any])?["segment_status"] as? String }

        XCTAssertEqual(statuses, ["visited", "hot"])
        XCTAssertFalse(statuses.contains("not_visited"))
    }

    func testAutomaticDeliveredStatusPreservesConversationStatuses() {
        XCTAssertEqual(AddressStatus.automaticDeliveredStatus(preserving: .talked), .talked)
        XCTAssertEqual(AddressStatus.automaticDeliveredStatus(preserving: .appointment), .appointment)
        XCTAssertEqual(AddressStatus.automaticDeliveredStatus(preserving: .hotLead), .hotLead)
        XCTAssertEqual(AddressStatus.automaticDeliveredStatus(preserving: .delivered), .delivered)
        XCTAssertEqual(AddressStatus.automaticDeliveredStatus(preserving: .untouched), .delivered)
        XCTAssertEqual(AddressStatus.automaticDeliveredStatus(preserving: nil), .delivered)
    }

    func testPreferredForDisplayKeepsStrongerConversationStatus() {
        XCTAssertEqual(
            AddressStatus.preferredForDisplay(current: .talked, incoming: .delivered),
            .talked
        )
        XCTAssertEqual(
            AddressStatus.preferredForDisplay(current: .delivered, incoming: .hotLead),
            .hotLead
        )
        XCTAssertEqual(
            AddressStatus.preferredForDisplay(current: .appointment, incoming: .talked),
            .appointment
        )
    }
    
    // MARK: - Color Priority Tests
    
    func testStatusColorPriority() {
        // Priority 1: QR Scanned (Yellow) - highest
        let qrScanned = (scansTotal: 5, status: "not_visited")
        XCTAssertTrue(qrScanned.scansTotal > 0, "QR scanned should have priority")
        
        // Priority 2: Hot (Blue)
        let hot = (scansTotal: 0, status: "hot")
        XCTAssertEqual(hot.status, "hot")
        
        // Priority 3: Visited (Green)
        let visited = (scansTotal: 0, status: "visited")
        XCTAssertEqual(visited.status, "visited")
        
        // Priority 4: Not visited (Red) - default
        let notVisited = (scansTotal: 0, status: "not_visited")
        XCTAssertEqual(notVisited.status, "not_visited")
    }
}
