import Foundation
import CoreLocation
import SwiftUI

// MARK: - Campaign Database Row

/// Campaign row as stored in Supabase campaigns table
struct CampaignDBRow: Codable {
    let id: UUID
    let title: String
    let description: String?
    let typeRaw: String?
    let addressSourceRaw: String?
    let scans: Int
    let conversions: Int
    let region: String?
    let tags: String?
    let status: CampaignStatus?
    let provisionStatus: CampaignProvisionStatus?
    let provisionSource: CampaignProvisionSource?
    let provisionPhase: CampaignProvisionPhase?
    let addressesReadyAt: Date?
    let mapReadyAt: Date?
    let optimizedAt: Date?
    let hasParcels: Bool?
    let buildingLinkConfidence: Double?
    let mapMode: CampaignMapMode?
    let coverageScore: Int?
    let dataQuality: CampaignDataQuality?
    let standardModeRecommended: Bool?
    let dataQualityReason: String?
    let dataConfidenceScore: Double?
    let dataConfidenceLabel: DataConfidenceLabel?
    let dataConfidenceReason: String?
    let dataConfidenceSummary: CampaignDataConfidenceSummary?
    let dataConfidenceUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let ownerId: UUID

    enum CodingKeys: String, CodingKey {
        case id, title, description, scans, conversions, region, tags, status
        case provisionStatus = "provision_status"
        case provisionSource = "provision_source"
        case provisionPhase = "provision_phase"
        case addressesReadyAt = "addresses_ready_at"
        case mapReadyAt = "map_ready_at"
        case optimizedAt = "optimized_at"
        case hasParcels = "has_parcels"
        case buildingLinkConfidence = "building_link_confidence"
        case mapMode = "map_mode"
        case coverageScore = "coverage_score"
        case dataQuality = "data_quality"
        case standardModeRecommended = "standard_mode_recommended"
        case dataQualityReason = "data_quality_reason"
        case typeRaw = "type"
        case addressSourceRaw = "address_source"
        case dataConfidenceScore = "data_confidence_score"
        case dataConfidenceLabel = "data_confidence_label"
        case dataConfidenceReason = "data_confidence_reason"
        case dataConfidenceSummary = "data_confidence_summary"
        case dataConfidenceUpdatedAt = "data_confidence_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerId = "owner_id"
    }

    var campaignType: CampaignType {
        guard let typeRaw, let parsed = CampaignType(dbValue: typeRaw) else {
            return .flyer
        }
        return parsed
    }

    var addressSource: AddressSource {
        guard let addressSourceRaw, let parsed = AddressSource(rawValue: addressSourceRaw) else {
            return .closestHome
        }
        return parsed
    }

    var dataConfidence: CampaignDataConfidenceSummary? {
        if let dataConfidenceSummary {
            return dataConfidenceSummary
        }

        guard
            let dataConfidenceScore,
            let dataConfidenceLabel,
            let dataConfidenceReason
        else {
            return nil
        }

        return CampaignDataConfidenceSummary(
            version: 1,
            score: dataConfidenceScore,
            label: dataConfidenceLabel,
            reason: dataConfidenceReason,
            metrics: CampaignDataConfidenceMetrics(
                addressesTotal: 0,
                addressesLinked: 0,
                linkedCoverage: 0,
                buildingLinkCount: 0,
                goldExactCount: 0,
                goldProximityCount: 0,
                goldUnlinkedCount: 0,
                silverCount: 0,
                bronzeCount: 0,
                lambdaCount: 0,
                manualCount: 0,
                otherCount: 0,
                unlinkedCount: 0,
                avgAddressScore: dataConfidenceScore,
                avgLinkConfidence: 0
            ),
            calculatedAt: dataConfidenceUpdatedAt
        )
    }
}

// MARK: - Campaign Address Database Row

/// Address row from campaign_addresses table with PostGIS geometry
struct CampaignAddressDBRow: Codable {
    let id: UUID
    let campaignId: UUID
    let formatted: String
    let postalCode: String?
    let source: String?
    let seq: Int?
    let visited: Bool
    let geom: GeoJSONPoint
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case formatted
        case postalCode = "postal_code"
        case source
        case seq
        case visited
        case geom
        case createdAt = "created_at"
    }
    
    /// Extract house number from formatted address
    var houseNumber: String? {
        return formatted.extractHouseNumber()
    }
}

// MARK: - Campaign Address View Row

/// Address row from campaign_addresses_v view with pre-computed geom_json
struct CampaignAddressViewRow: Codable {
    let id: UUID
    let campaignId: UUID
    let formatted: String
    let postalCode: String?
    let source: String?
    let seq: Int?
    let visited: Bool
    let geomJson: GeoJSONPoint  // Maps from geom_json column in view
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case formatted
        case postalCode = "postal_code"
        case source
        case seq
        case visited
        case geomJson = "geom_json"  // Map from geom_json column
        case createdAt = "created_at"
    }
    
    /// Computed property to access geom for compatibility
    var geom: GeoJSONPoint {
        return geomJson
    }
    
    /// Extract house number from formatted address
    var houseNumber: String? {
        return formatted.extractHouseNumber()
    }
}

// MARK: - Address Status

/// Visit/door status enum for campaign addresses
enum AddressStatus: String, Codable, CaseIterable {
    case none = "none"
    case untouched = "untouched"
    case noAnswer = "no_answer"
    case delivered = "delivered"
    case talked = "talked"
    case appointment = "appointment"
    case doNotKnock = "do_not_knock"
    case futureSeller = "future_seller"
    case hotLead = "hot_lead"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none: return "None"
        case .untouched: return "Untouched"
        case .noAnswer: return "Attempted"
        case .delivered: return "Delivered"
        case .talked: return "Talked"
        case .appointment: return "Appointment"
        case .doNotKnock: return "Do Not Knock"
        case .futureSeller: return "Follow Up"
        case .hotLead: return "Hot Lead"
        }
    }

    /// Short description for UI
    var description: String {
        switch self {
        case .none: return "No status set"
        case .untouched: return "Not yet visited"
        case .noAnswer: return "Attempted"
        case .delivered: return "Flyer delivered"
        case .talked: return "Spoke with resident"
        case .appointment: return "Appointment scheduled"
        case .doNotKnock: return "Do not knock"
        case .futureSeller: return "Follow up"
        case .hotLead: return "Hot lead"
        }
    }

    /// SF Symbol name for UI
    var iconName: String {
        switch self {
        case .none: return "circle"
        case .untouched: return "circle"
        case .noAnswer: return "door.left.hand.closed"
        case .delivered: return "envelope.fill"
        case .talked: return "person.wave.2.fill"
        case .appointment: return "calendar"
        case .doNotKnock: return "hand.raised.fill"
        case .futureSeller: return "arrow.uturn.right.circle.fill"
        case .hotLead: return "flame.fill"
        }
    }

    /// SwiftUI Color for UI
    var tintColor: Color {
        switch self {
        case .none: return .gray
        case .untouched: return .gray
        case .noAnswer: return .red
        case .delivered: return .blue
        case .talked: return .green
        case .appointment: return .yellow
        case .doNotKnock: return .black
        case .futureSeller: return .yellow
        case .hotLead: return .yellow
        }
    }

    /// Map status to the map layer's expected palette buckets.
    var mapLayerStatus: String {
        switch self {
        case .talked: return "hot"
        case .appointment, .hotLead, .futureSeller: return "hot_lead"
        case .doNotKnock: return "do_not_knock"
        case .noAnswer: return "no_answer"
        case .delivered: return "visited"
        case .none, .untouched: return "not_visited"
        }
    }

    /// Value safe to send to `record_campaign_address_outcome` / DB CHECK constraints (`untouched` is UI-only).
    var persistedRPCValue: String {
        switch self {
        case .untouched: return AddressStatus.none.rawValue
        default: return rawValue
        }
    }

    /// Preserves richer outcomes when automatic flyer-delivered signals arrive later.
    static func automaticDeliveredStatus(preserving existing: AddressStatus?) -> AddressStatus {
        guard let existing else { return .delivered }
        switch existing {
        case .talked, .appointment, .hotLead, .doNotKnock, .futureSeller:
            return existing
        case .none, .untouched, .noAnswer, .delivered:
            return .delivered
        }
    }

    /// Chooses the strongest status for display when local and fetched values race.
    static func preferredForDisplay(current: AddressStatus?, incoming: AddressStatus) -> AddressStatus {
        guard let current else { return incoming }
        return current.displayPriority > incoming.displayPriority ? current : incoming
    }

    private var displayPriority: Int {
        switch self {
        case .none, .untouched:
            return 0
        case .noAnswer, .delivered:
            return 1
        case .futureSeller:
            return 2
        case .doNotKnock:
            return 3
        case .talked:
            return 4
        case .appointment:
            return 5
        case .hotLead:
            return 6
        }
    }
}

/// Address status row from address_statuses table.
/// Decodes `id` from "id" or falls back to "address_id" so the app always has a stable UUID for Identifiable.
struct AddressStatusRow: Decodable, Identifiable {
    let id: UUID
    let addressId: UUID
    let campaignId: UUID
    let status: AddressStatus
    let lastVisitedAt: Date?
    let notes: String?
    let visitCount: Int
    let lastActionBy: UUID?
    let lastSessionId: UUID?
    let lastHomeEventId: UUID?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case addressId = "address_id"
        case campaignAddressId = "campaign_address_id"
        case campaignId = "campaign_id"
        case status
        case lastVisitedAt = "last_visited_at"
        case notes
        case visitCount = "visit_count"
        case lastActionBy = "last_action_by"
        case lastSessionId = "last_session_id"
        case lastHomeEventId = "last_home_event_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let cid = try c.decodeIfPresent(UUID.self, forKey: .campaignAddressId) {
            addressId = cid
        } else {
            addressId = try c.decode(UUID.self, forKey: .addressId)
        }
        // Use "id" if present, otherwise use campaign_addresses.id as the stable id
        if let decodedId = try? c.decode(UUID.self, forKey: .id) {
            id = decodedId
        } else {
            id = addressId
        }
        campaignId = try c.decode(UUID.self, forKey: .campaignId)
        let statusRaw = try c.decode(String.self, forKey: .status)
        switch statusRaw {
        case "untouched":
            status = .none
        default:
            status = AddressStatus(rawValue: statusRaw) ?? .none
        }
        lastVisitedAt = try c.decodeIfPresent(Date.self, forKey: .lastVisitedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        visitCount = try c.decodeIfPresent(Int.self, forKey: .visitCount) ?? 0
        lastActionBy = try c.decodeIfPresent(UUID.self, forKey: .lastActionBy)
        lastSessionId = try c.decodeIfPresent(UUID.self, forKey: .lastSessionId)
        lastHomeEventId = try c.decodeIfPresent(UUID.self, forKey: .lastHomeEventId)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
    }
}

// MARK: - GeoJSON Point

/// GeoJSON Point structure returned by ST_AsGeoJSON
struct GeoJSONPoint: Codable {
    let type: String // "Point"
    let coordinates: [Double] // [lon, lat] - PostGIS order
    
    /// Convert to CLLocationCoordinate2D (lat, lon order)
    var coordinate: CLLocationCoordinate2D {
        guard coordinates.count >= 2 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        // coordinates[0] = longitude, coordinates[1] = latitude
        return CLLocationCoordinate2D(
            latitude: coordinates[1],
            longitude: coordinates[0]
        )
    }
    
    /// Create from CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) {
        self.type = "Point"
        self.coordinates = [coordinate.longitude, coordinate.latitude]
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        coordinates = try container.decode([Double].self, forKey: .coordinates)
    }
    
    enum CodingKeys: String, CodingKey {
        case type, coordinates
    }
}

// MARK: - Helpers

extension CampaignAddress {
    /// Convert to JSONB format for RPC insert with PostGIS
    func toDBJSON() -> [String: Any] {
        var json: [String: Any] = [
            "formatted": address,
            "source": "mapbox",  // Set default source
            "seq": 0,
            "visited": false
        ]
        
        if let coord = coordinate {
            // PostGIS ST_MakePoint expects (lon, lat)
            json["lon"] = coord.longitude
            json["lat"] = coord.latitude
        }
        
        return json
    }
}
