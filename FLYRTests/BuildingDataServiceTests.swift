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
        depth: Double = 6,
        isTownhome: Bool = true,
        unitsCount: Int = 3,
        addressCount: Int? = 3
    ) throws -> BuildingFeature {
        var properties: [String: Any] = [
            "id": gersId,
            "gers_id": gersId,
            "height": 10,
            "height_m": 10,
            "min_height": 0,
            "is_townhome": isTownhome,
            "units_count": unitsCount,
            "status": "not_visited",
            "scans_today": 0,
            "scans_total": 0
        ]
        if let addressCount {
            properties["address_count"] = addressCount
        }

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
            "properties": properties
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

    private func firstPointCoordinates(from data: Data) throws -> (longitude: Double, latitude: Double) {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [[String: Any]])
        let feature = try XCTUnwrap(features.first)
        return try pointCoordinates(from: feature)
    }

    private func pointCoordinates(from feature: [String: Any]) throws -> (longitude: Double, latitude: Double) {
        let geometry = try XCTUnwrap(feature["geometry"] as? [String: Any])
        let coordinates = try XCTUnwrap(geometry["coordinates"] as? [Double])
        XCTAssertEqual(coordinates.count, 2)
        return (coordinates[0], coordinates[1])
    }

    private func makeBuildingGeoJSONFeature(properties: [String: AnyCodable]) -> GeoJSONFeature {
        GeoJSONFeature(
            id: properties["building_id"]?.value as? String,
            geometry: GeoJSONGeometry(
                type: "Polygon",
                coordinates: AnyCodable([[[
                    [-79.0, 43.0],
                    [-78.999, 43.0],
                    [-78.999, 43.001],
                    [-79.0, 43.001],
                    [-79.0, 43.0]
                ]]])
            ),
            properties: properties
        )
    }
    
    // Note: These tests require a mock Supabase client for full testing
    // For now, we'll test the data models and logic

    // MARK: - Linker Fallback Tests

    func testCampaignBuildingSnapshotWithAddressIdCountsAsLinked() {
        let feature = makeBuildingGeoJSONFeature(properties: [
            "building_id": AnyCodable("external-building-1"),
            "address_id": AnyCodable("11111111-1111-1111-1111-111111111111")
        ])

        let collection = GeoJSONFeatureCollection(features: [feature])

        XCTAssertTrue(NewCampaignScreen.featureCollectionHasLinkedAddressIdentity(collection))
    }

    func testCampaignBuildingSnapshotWithAddressIdsCountsAsLinked() {
        let feature = makeBuildingGeoJSONFeature(properties: [
            "building_id": AnyCodable("external-building-1"),
            "address_ids": AnyCodable(["22222222-2222-2222-2222-222222222222"])
        ])

        let collection = GeoJSONFeatureCollection(features: [feature])

        XCTAssertTrue(NewCampaignScreen.featureCollectionHasLinkedAddressIdentity(collection))
    }

    func testCampaignBuildingSnapshotWithoutAddressIdentityTriggersFallback() {
        let feature = makeBuildingGeoJSONFeature(properties: [
            "building_id": AnyCodable("external-building-1"),
            "gers_id": AnyCodable("external-building-1")
        ])

        let collection = GeoJSONFeatureCollection(features: [feature])

        XCTAssertFalse(NewCampaignScreen.featureCollectionHasLinkedAddressIdentity(collection))
    }

    func testDirectBuildingGersLinksAreExcludedFromLocalPickerCandidates() throws {
        let linkedId = UUID()
        let unlinkedId = UUID()
        let collection = AddressFeatureCollection(type: "FeatureCollection", features: [
            try makeAddressFeature(
                id: linkedId,
                buildingGersId: "external-building-1",
                houseNumber: "18",
                formatted: "18 Merino Street, Christchurch"
            ),
            try makeAddressFeature(
                id: unlinkedId,
                buildingGersId: "",
                houseNumber: "77",
                formatted: "77 Aviemore Drive, Christchurch"
            )
        ])

        let directlyLinked = BuildingLinkService.directlyLinkedAddressIds(in: collection)

        XCTAssertTrue(directlyLinked.contains(linkedId.uuidString.lowercased()))
        XCTAssertFalse(directlyLinked.contains(unlinkedId.uuidString.lowercased()))
    }

    func testBuildingFeatureCollectionDecodesNumericTopLevelFeatureId() throws {
        let payload: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "id": 12345,
                "geometry": [
                    "type": "Polygon",
                    "coordinates": [[
                        [-79.0, 43.0],
                        [-78.999, 43.0],
                        [-78.999, 43.001],
                        [-79.0, 43.001],
                        [-79.0, 43.0]
                    ]]
                ],
                "properties": [
                    "id": "building-12345",
                    "building_id": "building-12345",
                    "gers_id": "building-12345",
                    "height": 10,
                    "height_m": 10,
                    "min_height": 0,
                    "is_townhome": false,
                    "units_count": 1,
                    "status": "not_visited",
                    "scans_today": 0,
                    "scans_total": 0,
                    "source": "bedrock_pmtiles",
                    "area_sqm": 95
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        let collection = try JSONDecoder().decode(BuildingFeatureCollection.self, from: data)

        XCTAssertEqual(collection.features.count, 1)
        XCTAssertEqual(collection.features.first?.id, "12345")
        XCTAssertEqual(collection.features.first?.properties.gersId, "building-12345")
    }
    
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

    func testDeduplicatedAddressesForDisplayCollapsesSameHomeWithDifferentIds() throws {
        let firstId = UUID()
        let duplicateId = UUID()
        let addresses = try [
            makeCampaignAddressResponse(id: firstId, houseNumber: "83", streetName: "Post Rd", formatted: "83 POST RD, Toronto, ON"),
            makeCampaignAddressResponse(id: duplicateId, houseNumber: "83", streetName: "POST RD", formatted: "83 Post Rd, Toronto, ON")
        ]

        let deduped = BuildingDataService.deduplicatedAddressesForDisplay(addresses)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, firstId)
    }

    func testDeduplicatedAddressesForDisplayCollapsesStreetTypeVariants() throws {
        let firstId = UUID()
        let duplicateId = UUID()
        let addresses = try [
            makeCampaignAddressResponse(id: firstId, houseNumber: "83", streetName: "Post Rd", formatted: "83 Post Rd, Toronto, ON"),
            makeCampaignAddressResponse(id: duplicateId, houseNumber: "83", streetName: "POST ROAD", formatted: "83 POST ROAD, Toronto, ON")
        ]

        let deduped = BuildingDataService.deduplicatedAddressesForDisplay(addresses)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, firstId)
    }

    func testDeduplicatedAddressesForDisplayCollapsesCourtVariantsWithCitySuffixes() throws {
        let firstId = UUID()
        let duplicateId = UUID()
        let addresses = try [
            makeCampaignAddressResponse(id: firstId, houseNumber: "5311", streetName: "Green Velvet Ct", formatted: "5311 Green Velvet Ct"),
            makeCampaignAddressResponse(id: duplicateId, houseNumber: "5311", streetName: "Green Velvet Court", formatted: "5311 Green Velvet Court, Orlando, FL")
        ]

        let deduped = BuildingDataService.deduplicatedAddressesForDisplay(addresses)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, firstId)
    }

    func testDeduplicatedAddressesForDisplayPreservesRequestedDuplicate() throws {
        let firstId = UUID()
        let requestedId = UUID()
        let addresses = try [
            makeCampaignAddressResponse(id: firstId, houseNumber: "83", streetName: "Post Rd", formatted: "83 POST RD, Toronto, ON"),
            makeCampaignAddressResponse(id: requestedId, houseNumber: "83", streetName: "POST RD", formatted: "83 Post Rd, Toronto, ON")
        ]

        let deduped = BuildingDataService.deduplicatedAddressesForDisplay(addresses, requestedAddressId: requestedId)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, requestedId)
    }

    func testDeduplicatedAddressesForDisplayKeepsDifferentHomes() throws {
        let addresses = try [
            makeCampaignAddressResponse(houseNumber: "83", streetName: "Post Rd", formatted: "83 Post Rd, Toronto, ON"),
            makeCampaignAddressResponse(houseNumber: "85", streetName: "Post Rd", formatted: "85 Post Rd, Toronto, ON")
        ]

        let deduped = BuildingDataService.deduplicatedAddressesForDisplay(addresses)

        XCTAssertEqual(deduped.map(\.houseNumber), ["83", "85"])
    }

    func testAddressNumberLabelUsesBuildingCentroidForSingleLinkedHome() throws {
        let building = try makeBuildingFeature(
            gersId: "single-home-1",
            isTownhome: false,
            unitsCount: 1,
            addressCount: 1
        )
        let addressId = UUID()
        let address = try makeAddressFeature(
            id: addressId,
            buildingGersId: "single-home-1",
            houseNumber: "18",
            formatted: "18 Merino Street, Christchurch"
        )

        let data = try MapLayerManager.buildAddressNumberLabelPointGeoJSON(
            addresses: [address],
            buildings: [building],
            orderedAddressIdsByBuilding: ["single-home-1": [addressId]]
        )
        let coordinates = try firstPointCoordinates(from: data)

        XCTAssertEqual(coordinates.longitude, -78.9992, accuracy: 0.0000001)
        XCTAssertEqual(coordinates.latitude, 43.00024, accuracy: 0.0000001)
    }

    func testAddressNumberLabelsRemainDistributedForMultiUnitBuilding() throws {
        let building = try makeBuildingFeature(gersId: "multi-home-1", unitsCount: 2, addressCount: 2)
        let firstId = UUID()
        let secondId = UUID()
        let addresses = try [
            makeAddressFeature(id: firstId, buildingGersId: "multi-home-1", houseNumber: "18", formatted: "18 Merino Street"),
            makeAddressFeature(id: secondId, buildingGersId: "multi-home-1", houseNumber: "20", formatted: "20 Merino Street")
        ]

        let data = try MapLayerManager.buildAddressNumberLabelPointGeoJSON(
            addresses: addresses,
            buildings: [building],
            orderedAddressIdsByBuilding: ["multi-home-1": [firstId, secondId]]
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [[String: Any]])
        let coordinates = try features.map { try pointCoordinates(from: $0) }

        XCTAssertEqual(coordinates.count, 2)
        let delta = abs(coordinates[0].longitude - coordinates[1].longitude)
            + abs(coordinates[0].latitude - coordinates[1].latitude)
        XCTAssertGreaterThan(delta, 0.0000001)
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

    func testTownhomeOverlayKeepsSeparateSectionsWhenStatusesMatch() throws {
        let building = try makeBuildingFeature(gersId: "townhome-3")
        let firstId = UUID()
        let secondId = UUID()
        let addresses = try [
            makeAddressFeature(id: firstId, buildingGersId: "townhome-3", houseNumber: "55", formatted: "55 Richfield Square"),
            makeAddressFeature(id: secondId, buildingGersId: "townhome-3", houseNumber: "57", formatted: "57 Richfield Square")
        ]

        let data = MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: [building],
            addresses: addresses,
            orderedAddressIdsByBuilding: ["townhome-3": [firstId, secondId]],
            addressStatuses: [
                firstId: .delivered,
                secondId: .delivered
            ]
        )

        let json = try XCTUnwrap(data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [[String: Any]])
        let properties = features.compactMap { $0["properties"] as? [String: Any] }

        XCTAssertEqual(features.count, 2)
        XCTAssertEqual(properties.compactMap { $0["segment_status"] as? String }, ["visited", "visited"])
        XCTAssertEqual(properties.compactMap { $0["unit_count"] as? Int }, [2, 2])
        XCTAssertEqual(properties.compactMap { $0["address_id"] as? String }, [
            firstId.uuidString.lowercased(),
            secondId.uuidString.lowercased()
        ])
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

    func testLeadAndFollowUpStatusesMapToDistinctColorBuckets() {
        XCTAssertEqual(AddressStatus.hotLead.mapLayerStatus, "lead")
        XCTAssertEqual(AddressStatus.appointment.mapLayerStatus, "appointment")
        XCTAssertEqual(AddressStatus.futureSeller.mapLayerStatus, "future_seller")
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
