import Foundation
import CoreLocation

enum UnlinkedHomeAddressResolutionKind {
    case existingCampaignAddress
    case reverseGeocodedPin
}

struct UnlinkedHomeAddressResolution {
    let addressId: UUID
    let kind: UnlinkedHomeAddressResolutionKind
    let candidate: BuildingAddressCandidate
    let createdAddress: CampaignAddressResponse?
    let coordinate: CLLocationCoordinate2D
}

final class UnlinkedHomeAddressResolver {
    static let shared = UnlinkedHomeAddressResolver()

    private init() {}

    func resolve(
        campaignId: String,
        buildingId: String,
        buildingIdentifiers: [String] = [],
        seedCoordinate: CLLocationCoordinate2D,
        userConfirmed: Bool
    ) async throws -> UnlinkedHomeAddressResolution {
        let response = try await BuildingLinkService.shared.fetchAddressCandidates(
            campaignId: campaignId,
            buildingId: buildingId,
            buildingIdentifiers: buildingIdentifiers,
            radiusMeters: 60,
            limit: 15,
            seedCoordinate: seedCoordinate,
            forceReverseGeocode: true
        )

        guard let reverseCandidate = response.candidates.first(where: \.isReverseGeocode) else {
            throw NSError(
                domain: "UnlinkedHomeAddressResolver",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Reverse geocode did not return an address for this home."]
            )
        }

        if let matchingCampaignCandidate = exactCampaignAddressMatch(
            for: reverseCandidate,
            in: response.candidates
        ) {
            try await BuildingLinkService.shared.linkAddressToBuilding(
                campaignId: campaignId,
                buildingId: buildingId,
                addressId: matchingCampaignCandidate.id,
                coordinate: seedCoordinate
            )
            return UnlinkedHomeAddressResolution(
                addressId: matchingCampaignCandidate.id,
                kind: .existingCampaignAddress,
                candidate: matchingCampaignCandidate,
                createdAddress: nil,
                coordinate: seedCoordinate
            )
        }

        let created = try await BuildingLinkService.shared.createManualAddress(
            campaignId: campaignId,
            input: ManualAddressCreateInput(
                coordinate: seedCoordinate,
                formatted: reverseCandidate.displayAddress,
                houseNumber: reverseCandidate.houseNumber,
                streetName: reverseCandidate.resolvedStreetName,
                locality: reverseCandidate.locality,
                region: reverseCandidate.region,
                postalCode: reverseCandidate.postalCode,
                country: reverseCandidate.country,
                buildingId: buildingId,
                addressProvenance: "mapbox_reverse_geocode",
                userConfirmed: userConfirmed
            )
        )

        return UnlinkedHomeAddressResolution(
            addressId: created.address.id,
            kind: .reverseGeocodedPin,
            candidate: reverseCandidate,
            createdAddress: created.address,
            coordinate: seedCoordinate
        )
    }

    func exactCampaignAddressMatch(
        for reverseCandidate: BuildingAddressCandidate,
        in candidates: [BuildingAddressCandidate]
    ) -> BuildingAddressCandidate? {
        candidates.first { candidate in
            guard !candidate.isReverseGeocode else { return false }
            return Self.addressesMatch(
                reverseHouseNumber: reverseCandidate.houseNumber,
                reverseStreetName: reverseCandidate.resolvedStreetName,
                reversePostalCode: reverseCandidate.postalCode,
                reverseFormatted: reverseCandidate.displayAddress,
                candidateHouseNumber: candidate.houseNumber,
                candidateStreetName: candidate.resolvedStreetName,
                candidatePostalCode: candidate.postalCode,
                candidateFormatted: candidate.displayAddress
            )
        }
    }

    static func campaignAddressMatches(
        reverseCandidate: BuildingAddressCandidate,
        houseNumber: String?,
        streetName: String?,
        postalCode: String?,
        formatted: String?
    ) -> Bool {
        addressesMatch(
            reverseHouseNumber: reverseCandidate.houseNumber,
            reverseStreetName: reverseCandidate.resolvedStreetName,
            reversePostalCode: reverseCandidate.postalCode,
            reverseFormatted: reverseCandidate.displayAddress,
            candidateHouseNumber: houseNumber,
            candidateStreetName: streetName,
            candidatePostalCode: postalCode,
            candidateFormatted: formatted
        )
    }

    static func addressesMatch(
        reverseHouseNumber: String?,
        reverseStreetName: String?,
        reversePostalCode: String?,
        reverseFormatted: String?,
        candidateHouseNumber: String?,
        candidateStreetName: String?,
        candidatePostalCode: String?,
        candidateFormatted: String?
    ) -> Bool {
        guard let reverseIdentity = normalizedAddressIdentityParts(
            houseNumber: reverseHouseNumber,
            streetName: reverseStreetName,
            postalCode: reversePostalCode,
            formatted: reverseFormatted
        ),
        let candidateIdentity = normalizedAddressIdentityParts(
            houseNumber: candidateHouseNumber,
            streetName: candidateStreetName,
            postalCode: candidatePostalCode,
            formatted: candidateFormatted
        ) else {
            return false
        }

        guard reverseIdentity.primary == candidateIdentity.primary else { return false }
        if let reversePostal = reverseIdentity.postalCode,
           let candidatePostal = candidateIdentity.postalCode {
            return reversePostal == candidatePostal
        }
        return true
    }

    static func normalizedAddressIdentity(
        houseNumber: String?,
        streetName: String?
    ) -> String? {
        normalizedAddressIdentity(
            houseNumber: houseNumber,
            streetName: streetName,
            postalCode: nil,
            formatted: nil
        )
    }

    static func normalizedAddressIdentity(
        houseNumber: String?,
        streetName: String?,
        postalCode: String?,
        formatted: String?
    ) -> String? {
        normalizedAddressIdentityParts(
            houseNumber: houseNumber,
            streetName: streetName,
            postalCode: postalCode,
            formatted: formatted
        )?.primary
    }

    private static func normalizedAddressIdentityParts(
        houseNumber: String?,
        streetName: String?,
        postalCode: String?,
        formatted: String?
    ) -> NormalizedAddressIdentity? {
        let parsed = parsedAddressParts(from: formatted)
        guard let house = normalizedHouseNumber(houseNumber) ?? parsed.houseNumber,
              let street = normalizedStreetName(streetName) ?? parsed.streetName else {
            return nil
        }

        return NormalizedAddressIdentity(
            primary: "\(house)|\(street)",
            postalCode: normalizedPostalCode(postalCode) ?? parsed.postalCode
        )
    }

    private static func parsedAddressParts(from formatted: String?) -> (houseNumber: String?, streetName: String?, postalCode: String?) {
        let trimmed = formatted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return (nil, nil, nil) }

        let firstAddressLine = trimmed
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? trimmed
        let tokens = firstAddressLine
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let houseNumber = tokens.first.flatMap(normalizedHouseNumber)
        let streetName = tokens.count > 1
            ? normalizedStreetName(tokens.dropFirst().joined(separator: " "))
            : nil

        let postalCandidates = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let postalCode = postalCandidates
            .reversed()
            .compactMap(normalizedPostalCode)
            .first { $0.count >= 4 && $0.count <= 10 && $0.contains(where: \.isNumber) }

        return (houseNumber, streetName, postalCode)
    }

    private static func normalizedPostalCode(_ value: String?) -> String? {
        let normalized = value?
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized?.isEmpty == false ? normalized : nil
    }

    private struct NormalizedAddressIdentity {
        let primary: String
        let postalCode: String?
    }

    private static func normalizedHouseNumber(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
        return normalized?.isEmpty == false ? normalized : nil
    }

    private static func normalizedStreetName(_ value: String?) -> String? {
        let raw = value?
            .lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ") ?? ""
        let words = raw
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        let normalizedWords = words.map { word -> String in
            switch word {
            case "st", "str": return "street"
            case "rd": return "road"
            case "ave", "av": return "avenue"
            case "blvd": return "boulevard"
            case "dr": return "drive"
            case "ct": return "court"
            case "cres": return "crescent"
            case "ln": return "lane"
            case "pl": return "place"
            case "trl": return "trail"
            case "pkwy": return "parkway"
            case "hwy": return "highway"
            default: return word
            }
        }

        let normalized = normalizedWords.joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}
