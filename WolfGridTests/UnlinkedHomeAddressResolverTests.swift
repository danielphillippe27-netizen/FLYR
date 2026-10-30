import XCTest
@testable import WolfGrid

final class UnlinkedHomeAddressResolverTests: XCTestCase {
    func testLinkingBuildingPreservesParcelAndLabelMetadata() throws {
        let original = AddressProperties(
            id: UUID().uuidString, gersId: "address-point", buildingGersId: "old-building",
            linkedBuildingId: "old-building", houseNumber: "296", houseNumberLabel: "296",
            streetName: "Northglen Boulevard", postalCode: "L1C", locality: "Bowmanville",
            formatted: "296 Northglen Boulevard", source: "campaign", featureType: "address",
            parcelId: "266930338", campaignParcelId: "campaign-parcel",
            hasBuildingLink: false, hasParcelLink: true, labelVisibilityMode: "always",
            pinPlacement: "parcel", labelAnchorLon: -78.7, labelAnchorLat: 43.9,
            labelGroupKey: "group", labelGroupIndex: 0, labelGroupCount: 1, labelPriority: 10
        )
        let updated = original.linkingBuilding("new-building")
        XCTAssertEqual(updated.buildingGersId, "new-building")
        XCTAssertEqual(updated.linkedBuildingId, "new-building")
        XCTAssertEqual(updated.hasBuildingLink, true)
        var before = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var after = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(updated)) as? [String: Any])
        for key in ["building_gers_id", "linked_building_id", "has_building_link"] {
            before.removeValue(forKey: key)
            after.removeValue(forKey: key)
        }
        XCTAssertEqual(before as NSDictionary, after as NSDictionary,
                       "Linking must retain parcel identifiers, address identity and label placement")
    }

    func testStreetSuffixNormalizationMatchesCommonAbbreviations() {
        XCTAssertEqual(
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: "123",
                streetName: "Main St."
            ),
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: "123",
                streetName: "Main Street"
            )
        )
    }

    func testDifferentHouseNumbersDoNotMatch() {
        XCTAssertNotEqual(
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: "123",
                streetName: "Main Street"
            ),
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: "125",
                streetName: "Main Street"
            )
        )
    }

    func testMissingHouseNumberDoesNotProduceIdentity() {
        XCTAssertNil(
            UnlinkedHomeAddressResolver.normalizedAddressIdentity(
                houseNumber: nil,
                streetName: "Main Street"
            )
        )
    }

    func testFormattedReverseGeocodeMatchesStructuredCampaignAddress() {
        XCTAssertTrue(
            UnlinkedHomeAddressResolver.addressesMatch(
                reverseHouseNumber: nil,
                reverseStreetName: nil,
                reversePostalCode: nil,
                reverseFormatted: "18 MERINO STREET, CHRISTCHURCH, 8083",
                candidateHouseNumber: "18",
                candidateStreetName: "Merino St.",
                candidatePostalCode: "8083",
                candidateFormatted: "18 Merino St"
            )
        )
    }

    func testPostalCodeFormattingDifferencesStillMatch() {
        XCTAssertTrue(
            UnlinkedHomeAddressResolver.addressesMatch(
                reverseHouseNumber: "18",
                reverseStreetName: "Merino Street",
                reversePostalCode: "80 83",
                reverseFormatted: nil,
                candidateHouseNumber: "18",
                candidateStreetName: "Merino St",
                candidatePostalCode: "8083",
                candidateFormatted: nil
            )
        )
    }

    func testReverseGeocodeCandidateResolvesExistingCampaignCandidate() {
        let reverseCandidate = makeCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            candidateType: "reverse_geocode",
            isSynthetic: true,
            formatted: "18 MERINO STREET, CHRISTCHURCH, 8083",
            houseNumber: nil,
            streetName: nil,
            postalCode: nil
        )
        let existingCandidate = makeCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            formatted: "18 Merino St",
            houseNumber: "18",
            streetName: "Merino St",
            postalCode: "8083"
        )

        let match = UnlinkedHomeAddressResolver.shared.exactCampaignAddressMatch(
            for: reverseCandidate,
            in: [reverseCandidate, existingCandidate]
        )

        XCTAssertEqual(match?.id, existingCandidate.id)
    }

    func testReverseGeocodeDisplayUsesStreetLineOnly() {
        let candidate = makeCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            candidateType: "reverse_geocode",
            isSynthetic: true,
            formatted: "5311 Green Velvet Court, Orlando, Florida 32808, United States",
            houseNumber: "5311",
            streetName: "Green Velvet Court",
            locality: "Orlando",
            region: "Florida",
            postalCode: "32808"
        )

        XCTAssertEqual(candidate.displayAddress, "5311 Green Velvet Court")
        XCTAssertEqual(candidate.locality, "Orlando")
        XCTAssertEqual(candidate.region, "Florida")
    }

    func testReverseGeocodeDisplayFallsBackToFirstFormattedLine() {
        let candidate = makeCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            candidateType: "reverse_geocode",
            isSynthetic: true,
            formatted: "5311 Green Velvet Court, Orlando, Florida 32808, United States",
            houseNumber: nil,
            streetName: nil,
            postalCode: nil
        )

        XCTAssertEqual(candidate.displayAddress, "5311 Green Velvet Court")
    }

    func testReverseGeocodeAndExistingMatchStayAboveNearbySuggestions() {
        let nearby = makeCandidate(id: UUID(), formatted: "12 Main St", houseNumber: "12", streetName: "Main St", postalCode: nil)
        let other = makeCandidate(id: UUID(), formatted: "14 Main St", houseNumber: "14", streetName: "Main St", postalCode: nil)
        let reverse = makeCandidate(id: UUID(), candidateType: "reverse_geocode", isSynthetic: true,
                                    formatted: "16 Main St", houseNumber: "16", streetName: "Main St", postalCode: nil)
        XCTAssertEqual(UnlinkedHomeAddressResolver.reverseGeocodeFirst([nearby, other, reverse], matchedAddressIds: []).map(\.id),
                       [reverse.id, nearby.id, other.id])
        XCTAssertEqual(UnlinkedHomeAddressResolver.reverseGeocodeFirst([nearby, other], matchedAddressIds: [other.id]).map(\.id),
                       [other.id, nearby.id])
        XCTAssertEqual(UnlinkedHomeAddressResolver.reverseGeocodeFirst([nearby, other], matchedAddressIds: []).map(\.id),
                       [nearby.id, other.id])
    }

    func testAddressIndexReusesIdentitiesAndInvalidatesEdits() async throws {
        let index = CampaignAddressMatchIndex()
        let id = UUID()
        func feature(_ house: String) throws -> AddressFeature {
            let object: [String: Any] = ["type": "Feature", "id": id.uuidString,
                "geometry": ["type": "Point", "coordinates": [172.65, -43.53]],
                "properties": ["id": id.uuidString, "house_number": house,
                               "street_name": "Merino Street", "postal_code": "8083"]]
            return try JSONDecoder().decode(AddressFeature.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let candidate = makeCandidate(id: UUID(), formatted: "18 Merino St", houseNumber: "18", streetName: "Merino St", postalCode: "8083")
        await index.prepare(key: "source1", features: [try feature("18")])
        let warm = await index.match(candidate, key: "source1", features: [])
        XCTAssertEqual(warm?.properties.id, id.uuidString, "Warm lookup must use the prepared index")
        let wrongPostal = makeCandidate(id: UUID(), formatted: "18 Merino St", houseNumber: "18", streetName: "Merino St", postalCode: "9999")
        let mismatch = await index.match(wrongPostal, key: "source1", features: [])
        XCTAssertNil(mismatch, "An identity hit must still validate postal codes")
        await index.upsert(try feature("20"), from: "source1", to: "source2")
        let old = await index.match(candidate, key: "source2", features: [])
        XCTAssertNil(old, "Renaming a cached address must remove the old identity")
        let renamed = makeCandidate(id: UUID(), formatted: "20 Merino St", houseNumber: "20", streetName: "Merino St", postalCode: "8083")
        let new = await index.match(renamed, key: "source2", features: [])
        XCTAssertEqual(new?.properties.id, id.uuidString)
        let removed = await index.match(renamed, key: "source3", features: [])
        XCTAssertNil(removed, "A different source key must not keep a removed address")
    }

    private func makeCandidate(
        id: UUID,
        candidateType: String = "official",
        isSynthetic: Bool = false,
        formatted: String,
        houseNumber: String?,
        streetName: String?,
        locality: String? = nil,
        region: String? = nil,
        postalCode: String?
    ) -> BuildingAddressCandidate {
        BuildingAddressCandidate(
            id: id,
            candidateType: candidateType,
            isSynthetic: isSynthetic,
            formatted: formatted,
            houseNumber: houseNumber,
            streetName: streetName,
            locality: locality,
            region: region,
            postalCode: postalCode,
            source: "test",
            coordinate: CandidateCoordinate(longitude: 172.65, latitude: -43.53),
            distanceMeters: 0,
            score: 1,
            reason: "Test candidate",
            requiresConfirmation: false
        )
    }
}
