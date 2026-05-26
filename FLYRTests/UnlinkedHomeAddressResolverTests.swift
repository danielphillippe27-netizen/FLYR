import XCTest
@testable import FLYR

final class UnlinkedHomeAddressResolverTests: XCTestCase {
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
            postalCode: "32808"
        )

        XCTAssertEqual(candidate.displayAddress, "5311 Green Velvet Court")
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

    private func makeCandidate(
        id: UUID,
        candidateType: String = "official",
        isSynthetic: Bool = false,
        formatted: String,
        houseNumber: String?,
        streetName: String?,
        postalCode: String?
    ) -> BuildingAddressCandidate {
        BuildingAddressCandidate(
            id: id,
            candidateType: candidateType,
            isSynthetic: isSynthetic,
            formatted: formatted,
            houseNumber: houseNumber,
            streetName: streetName,
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
