import Foundation
import CoreLocation

private func resolveFarmAddressStatus(rawStatus: String?, visitedCount: Int) -> AddressStatus {
    let fallback: AddressStatus = visitedCount > 0 ? .delivered : .none
    guard let rawStatus else { return fallback }

    let normalized = rawStatus
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard !normalized.isEmpty else { return fallback }

    if normalized == AddressStatus.untouched.rawValue {
        return .none
    }

    return AddressStatus(rawValue: normalized) ?? fallback
}

struct FarmAddressViewRow: Identifiable {
    let farmAddressId: UUID
    let campaignAddressId: UUID?
    let farmId: UUID
    let campaignId: UUID?
    let gersId: String?
    let formatted: String
    let postalCode: String?
    let source: String?
    let houseNumber: String?
    let streetName: String?
    let locality: String?
    let region: String?
    let visitedCount: Int
    let lastVisitedAt: Date?
    let lastOutcomeStatus: String?
    let geomJson: GeoJSONPoint
    let createdAt: Date

    var id: UUID {
        campaignAddressId ?? farmAddressId
    }

    var geom: GeoJSONPoint {
        geomJson
    }

    var resolvedStatus: AddressStatus {
        resolveFarmAddressStatus(rawStatus: lastOutcomeStatus, visitedCount: visitedCount)
    }
}

struct FarmAddressDBRow: Decodable {
    let id: UUID
    let campaignAddressId: UUID?
    let farmId: UUID
    let gersId: String?
    let formatted: String
    let postalCode: String?
    let source: String?
    let houseNumber: String?
    let streetName: String?
    let locality: String?
    let region: String?
    let latitude: Double?
    let longitude: Double?
    let visitedCount: Int
    let lastVisitedAt: Date?
    let lastOutcomeStatus: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case campaignAddressId = "campaign_address_id"
        case farmId = "farm_id"
        case gersId = "gers_id"
        case formatted
        case postalCode = "postal_code"
        case source
        case houseNumber = "house_number"
        case streetName = "street_name"
        case locality
        case region
        case latitude
        case longitude
        case visitedCount = "visited_count"
        case lastVisitedAt = "last_visited_at"
        case lastOutcomeStatus = "last_outcome_status"
        case createdAt = "created_at"
    }

    func toViewRow(campaignId: UUID?) -> FarmAddressViewRow? {
        guard let latitude, let longitude else { return nil }

        return FarmAddressViewRow(
            farmAddressId: id,
            campaignAddressId: campaignAddressId,
            farmId: farmId,
            campaignId: campaignId,
            gersId: gersId,
            formatted: formatted,
            postalCode: postalCode,
            source: source,
            houseNumber: houseNumber ?? formatted.extractHouseNumber(),
            streetName: streetName,
            locality: locality,
            region: region,
            visitedCount: visitedCount,
            lastVisitedAt: lastVisitedAt,
            lastOutcomeStatus: lastOutcomeStatus,
            geomJson: GeoJSONPoint(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            ),
            createdAt: createdAt
        )
    }
}

struct FarmTouchCycleRow: Decodable {
    let cycleNumber: Int

    enum CodingKeys: String, CodingKey {
        case cycleNumber = "cycle_number"
    }
}

struct FarmTouchAddressStatusDBRow: Decodable {
    let farmAddressId: UUID
    let campaignAddressId: UUID?
    let status: String
    let occurredAt: Date
    let updatedAt: Date?
    let farmTouch: FarmTouchCycleRow?

    enum CodingKeys: String, CodingKey {
        case farmAddressId = "farm_address_id"
        case campaignAddressId = "campaign_address_id"
        case status
        case occurredAt = "occurred_at"
        case updatedAt = "updated_at"
        case farmTouch = "farm_touches"
    }

    var mapAddressId: UUID {
        campaignAddressId ?? farmAddressId
    }

    var resolvedStatus: AddressStatus {
        resolveFarmAddressStatus(rawStatus: status, visitedCount: 1)
    }
}
