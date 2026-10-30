import Foundation
import CoreLocation

struct CachedBuildingLocation {
    let response: ManualAddressCreateResponse
    let coordinate: CLLocationCoordinate2D
    let linkedAddressIds: [UUID]
    let source: String?
}

/// A building can be worked before a street address is available. Its UUID is
/// the durable identity; geocoding only fills in the descriptive fields.
enum AutomaticBuildingLocation {
    static let provenance = "field_building_location"
    static let resolvedProvenance = "field_building_reverse_geocode"
    static let unresolvedProvenance = "field_building_location_unresolved"
    static let placeholder = "Property location"

    static func isAutomatic(_ provenance: String?) -> Bool {
        [Self.provenance, resolvedProvenance, unresolvedProvenance].contains(provenance ?? "")
    }

    static func unresolvedPayload(_ payload: ManualAddressCreateOutboxPayload) -> ManualAddressCreateOutboxPayload {
        ManualAddressCreateOutboxPayload(
            campaignId: payload.campaignId, addressId: payload.addressId,
            formatted: payload.formatted, houseNumber: payload.houseNumber, streetName: payload.streetName,
            locality: payload.locality, region: payload.region, postalCode: payload.postalCode, country: payload.country,
            buildingId: payload.buildingId, addressProvenance: unresolvedProvenance, userConfirmed: false,
            parcelId: payload.parcelId, campaignParcelId: payload.campaignParcelId, hasParcelLink: payload.hasParcelLink,
            latitude: payload.latitude, longitude: payload.longitude
        )
    }

    static func resolvedPayload(
        _ payload: ManualAddressCreateOutboxPayload,
        thoroughfare: String?,
        locality: String?,
        region: String?,
        postalCode: String?,
        country: String?
    ) -> ManualAddressCreateOutboxPayload? {
        let parts = (thoroughfare ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2,
              parts[0].range(of: #"^\d+[A-Za-z\-/]*$"#, options: .regularExpression) != nil else {
            // A road, city or postal code alone is not a house address.
            return nil
        }
        let house = String(parts[0])
        let street = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !street.isEmpty else { return nil }
        return ManualAddressCreateOutboxPayload(
            campaignId: payload.campaignId, addressId: payload.addressId,
            formatted: "\(house) \(street)", houseNumber: house, streetName: street,
            locality: locality, region: region, postalCode: postalCode, country: country,
            buildingId: payload.buildingId, addressProvenance: resolvedProvenance,
            // An estimate must not deduplicate this stable UUID onto another home.
            userConfirmed: false, parcelId: payload.parcelId,
            campaignParcelId: payload.campaignParcelId, hasParcelLink: payload.hasParcelLink,
            latitude: payload.latitude, longitude: payload.longitude
        )
    }

}

/// Deduplicate rapid taps, including taps from a newly presented map view.
/// Once persisted, the normal cached building/address link is authoritative.
@MainActor
final class UnlinkedBuildingLocationService {
    static let shared = UnlinkedBuildingLocationService()
    private var creations: [String: Task<ManualAddressCreateResponse, Error>] = [:]
    private let createAddress: @MainActor (String, ManualAddressCreateInput) async throws -> ManualAddressCreateResponse

    init(createAddress: @escaping @MainActor (String, ManualAddressCreateInput) async throws -> ManualAddressCreateResponse = { campaignId, input in
        try await BuildingLinkService.shared.createManualAddress(
            campaignId: campaignId, input: input, syncBehavior: .enqueueAndReturnLocal
        )
    }) {
        self.createAddress = createAddress
    }

    func create(campaignId: String, input: ManualAddressCreateInput) async throws -> ManualAddressCreateResponse {
        let key = "\(campaignId.lowercased()):\((input.buildingId ?? "").lowercased())"
        if let existing = creations[key] { return try await existing.value }
        let task = Task {
            try await createAddress(campaignId, input)
        }
        creations[key] = task
        defer { creations[key] = nil }
        return try await task.value
    }
}
