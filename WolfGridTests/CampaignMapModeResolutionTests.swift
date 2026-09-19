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

    func testStandardSessionCanExplicitlySwitchTo3DWithoutBuildings() {
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: false, hasRenderableBuildings: false,
            activeSession: true, sessionUses2D: false,
            mapboxAvailable: true, googleAvailable: true,
            standardMode: true, preferred2D: false
        ), .mapbox3D)
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: true, hasRenderableBuildings: true,
            activeSession: true, sessionUses2D: false,
            mapboxAvailable: true, googleAvailable: true,
            standardMode: true, preferred2D: true
        ), .google2D)
    }

    func testRendererPreferenceFallsBackWhenProviderIsUnavailable() {
        XCTAssertEqual(CampaignMapRendererDecision.resolve(
            dataResolved: true, hasRenderableBuildings: true,
            activeSession: true, sessionUses2D: false,
            mapboxAvailable: false, googleAvailable: true,
            standardMode: true, preferred2D: false
        ), .google2D)
        XCTAssertNil(CampaignMapRendererDecision.resolve(
            dataResolved: true, hasRenderableBuildings: true,
            activeSession: true, sessionUses2D: false,
            mapboxAvailable: false, googleAvailable: false,
            standardMode: true, preferred2D: true
        ))
    }

    @MainActor
    func testManualPinsKeepIdentityLocationAndStatusIn3DSource() throws {
        let id = UUID().uuidString
        for provenance in ["manual_pin", "field_manual_pin"] {
            let input: [String: Any] = [
                "type": "FeatureCollection",
                "features": [[
                    "type": "Feature", "id": id,
                    "geometry": ["type": "Point", "coordinates": [-79.38, 43.65]],
                    "properties": ["id": id, "source": provenance, "status": "talked"]
                ]]
            ]
            let data = try JSONSerialization.data(withJSONObject: input)
            let result = try MapLayerManager.convertAddressPointsToCirclePolygons(data)
            let collection = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
            let features = try XCTUnwrap(collection["features"] as? [[String: Any]])
            XCTAssertEqual(features.count, 1)
            let feature = try XCTUnwrap(features.first)
            XCTAssertEqual(feature["id"] as? String, id)
            let geometry = try XCTUnwrap(feature["geometry"] as? [String: Any])
            XCTAssertEqual(geometry["type"] as? String, "Point")
            XCTAssertEqual(geometry["coordinates"] as? [Double], [-79.38, 43.65])
            let properties = try XCTUnwrap(feature["properties"] as? [String: Any])
            XCTAssertEqual(properties["status"] as? String, "talked")
            XCTAssertEqual(properties["feature_type"] as? String, "manual_pin")
        }
    }

    func testPinHeightUsesSameReferenceAsHouseHeight() {
        XCTAssertEqual(MapLayerManager.manualPinRenderedHeight, 3.64, accuracy: 0.0001)
        XCTAssertEqual(
            MapLayerManager.manualPinRenderedHeight / (MapLayerManager.defaultBuildingExtrusionHeight * 0.6),
            7.0 / 6.0, accuracy: 0.0001
        )
    }

    @MainActor
    func testManualPinNumberSitsAtCapHeightAtThePinCoordinate() throws {
        let id = UUID().uuidString
        let payload: [String: Any] = [
            "type": "Feature", "id": id,
            "geometry": ["type": "Point", "coordinates": [-79.38, 43.65]],
            "properties": [
                "id": id, "source": "field_manual_pin", "feature_type": "manual_pin",
                "house_number": "128", "formatted": "128 Main Street",
                "label_anchor_lon": -79.4, "label_anchor_lat": 43.7,
                "label_visibility_mode": "address_mode_only"
            ]
        ]
        let address = try JSONDecoder().decode(AddressFeature.self, from: JSONSerialization.data(withJSONObject: payload))
        let data = try MapLayerManager.buildAddressNumberLabelPointGeoJSON(
            addresses: [address], buildings: [], orderedAddressIdsByBuilding: [:]
        )
        let collection = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try XCTUnwrap(collection["features"] as? [[String: Any]])
        let feature = try XCTUnwrap(features.first)
        let properties = try XCTUnwrap(feature["properties"] as? [String: Any])
        XCTAssertEqual(properties["house_number_label"] as? String, "128")
        XCTAssertEqual(try XCTUnwrap(properties["label_z_offset"] as? Double), 3.68, accuracy: 0.0001)
        let geometry = try XCTUnwrap(feature["geometry"] as? [String: Any])
        XCTAssertEqual(geometry["coordinates"] as? [Double], [-79.38, 43.65])
    }

    @MainActor
    func testSatellitePinFilterExcludesPreloadedAddressesAndKeepsManualPins() throws {
        func feature(source: String, type: String? = nil, label: String = "128 Main Street") throws -> AddressFeature {
            let id = UUID().uuidString
            var properties: [String: Any] = ["id": id, "source": source, "formatted": label, "label_visibility_mode": "address_mode_only"]
            if let type { properties["feature_type"] = type }
            let payload: [String: Any] = ["type": "Feature", "id": id, "properties": properties,
                "geometry": ["type": "Point", "coordinates": [-79.38, 43.65]]]
            return try JSONDecoder().decode(AddressFeature.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        for source in ["overture", "google", "mapbox", "import"] {
            XCTAssertFalse(MapLayerManager.isManualPinAddressFeature(try feature(source: source)))
        }
        for source in ["manual_pin", "field_manual_pin", "manual"] {
            XCTAssertTrue(MapLayerManager.isManualPinAddressFeature(try feature(source: source)))
        }
        XCTAssertTrue(MapLayerManager.isManualPinAddressFeature(try feature(source: "google", type: "field_manual_pin")))
        XCTAssertTrue(MapLayerManager.isManualPinAddressFeature(try feature(source: "", label: "Pinned Home 43.65000, -79.38000")))
    }

    @MainActor
    func testManualPinAndNumberClearHighestOverlappingRoof() throws {
        let id = UUID().uuidString
        let addressJSON: [String: Any] = ["type": "Feature", "id": id,
            "geometry": ["type": "Point", "coordinates": [-79.38, 43.65]],
            "properties": ["id": id, "source": "field_manual_pin", "house_number": "128", "formatted": "128 Main Street"]]
        let address = try JSONDecoder().decode(AddressFeature.self, from: JSONSerialization.data(withJSONObject: addressJSON))
        func building(height: Double, longitude: Double = -79.38) throws -> BuildingFeature {
            let buildingID = UUID().uuidString
            let json: [String: Any] = ["type": "Feature", "id": buildingID,
                "properties": ["id": buildingID, "gers_id": buildingID, "height": height, "height_m": height,
                    "address_ids": [UUID().uuidString]],
                "geometry": ["type": "Polygon", "coordinates": [[
                    [longitude-0.0001,43.6499], [longitude+0.0001,43.6499],
                    [longitude+0.0001,43.6501], [longitude-0.0001,43.6501], [longitude-0.0001,43.6499]
                ]]]]
            return try JSONDecoder().decode(BuildingFeature.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func properties(_ data: Data) throws -> [String: Any] {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let features = try XCTUnwrap(json["features"] as? [[String: Any]])
            let feature = try XCTUnwrap(features.first { ($0["id"] as? String)?.lowercased() == id.lowercased() })
            return try XCTUnwrap(feature["properties"] as? [String: Any])
        }
        // The 100 m input is clamped to the same 14 m reference used by rendering.
        // Unrelated explicit address IDs must not prevent geometric roof clearance.
        let roofs = try [building(height: 10), building(height: 100)]
        let marker = try properties(MapLayerManager.smartAddressMarkerPointCollection(
            addresses: [address], buildings: roofs, orderedAddressIdsByBuilding: [:]))
        let label = try properties(MapLayerManager.buildAddressNumberLabelPointGeoJSON(
            addresses: [address], buildings: roofs, orderedAddressIdsByBuilding: [:]))
        let translation = try XCTUnwrap(marker["manual_pin_translation"] as? [Double])
        XCTAssertEqual(translation[0], 0)
        XCTAssertEqual(translation[1], 0)
        XCTAssertEqual(translation[2] + MapLayerManager.manualPinRenderedHeight, 8.4 + 0.65, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(label["label_z_offset"] as? Double), 8.4 + 0.65 + 0.04, accuracy: 0.0001)
        let roofEdge = try properties(MapLayerManager.smartAddressMarkerPointCollection(
            addresses: [address], buildings: [building(height: 14, longitude: -79.38012)], orderedAddressIdsByBuilding: [:]))
        let edgeTranslation = try XCTUnwrap(roofEdge["manual_pin_translation"] as? [Double])
        XCTAssertEqual(edgeTranslation[2] + MapLayerManager.manualPinRenderedHeight, 8.4 + 0.65, accuracy: 0.0001)
        let outside = try properties(MapLayerManager.smartAddressMarkerPointCollection(
            addresses: [address], buildings: [building(height: 100, longitude: -79.4)], orderedAddressIdsByBuilding: [:]))
        XCTAssertEqual(outside["manual_pin_translation"] as? [Double], [0, 0, 0])
    }

    @MainActor
    func testRoofClearanceHandlesMissingAndInvalidHeights() {
        for height: Double? in [nil, .nan, .infinity, -1, 0] {
            XCTAssertEqual(MapLayerManager.manualPinBaseElevation(roofHeight: height), 0)
        }
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
