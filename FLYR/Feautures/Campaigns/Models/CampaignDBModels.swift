import Foundation
import CoreLocation
import SwiftUI

// MARK: - Campaign Database Row

/// Campaign row as stored in Supabase campaigns table
struct CampaignDBRow: Codable {
    let id: UUID
    let title: String
    let description: String?
    let scans: Int
    let conversions: Int
    let region: String?
    let tags: String?
    let status: CampaignStatus?
    let createdAt: Date
    let updatedAt: Date
    let ownerId: UUID

    enum CodingKeys: String, CodingKey {
        case id, title, description, scans, conversions, region, tags, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerId = "owner_id"
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
        case .noAnswer: return "No Answer"
        case .delivered: return "Delivered"
        case .talked: return "Talked"
        case .appointment: return "Appointment"
        case .doNotKnock: return "Do Not Knock"
        case .futureSeller: return "Future Seller"
        case .hotLead: return "Hot Lead"
        }
    }

    /// Short description for UI
    var description: String {
        switch self {
        case .none: return "No status set"
        case .untouched: return "Not yet visited"
        case .noAnswer: return "No one answered"
        case .delivered: return "Flyer delivered"
        case .talked: return "Spoke with resident"
        case .appointment: return "Appointment scheduled"
        case .doNotKnock: return "Do not knock"
        case .futureSeller: return "Future seller"
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
        case .futureSeller: return "house.fill"
        case .hotLead: return "flame.fill"
        }
    }

    /// SwiftUI Color for UI
    var tintColor: Color {
        switch self {
        case .none: return .gray
        case .untouched: return .gray
        case .noAnswer: return .flyrPrimary
        case .delivered: return .blue
        case .talked: return .green
        case .appointment: return .purple
        case .doNotKnock: return .red
        case .futureSeller: return .teal
        case .hotLead: return .red
        }
    }

    /// Map status to the map layer's expected values: "hot" (blue), "visited" (green), "not_visited" (red).
    var mapLayerStatus: String {
        switch self {
        case .talked, .appointment, .hotLead: return "hot"
        case .delivered, .doNotKnock, .futureSeller: return "visited"
        case .none, .untouched, .noAnswer: return "not_visited"
        }
    }
}

/// Address status row from address_statuses table.
/// Decodes `id` from "id" or falls back to "address_id" so the app always has a stable UUID for Identifiable.
struct AddressStatusRow: Codable, Identifiable {
    let id: UUID
    let addressId: UUID
    let campaignId: UUID
    let status: AddressStatus
    let lastVisitedAt: Date?
    let notes: String?
    let visitCount: Int
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case addressId = "address_id"
        case campaignId = "campaign_id"
        case status
        case lastVisitedAt = "last_visited_at"
        case notes
        case visitCount = "visit_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addressId = try c.decode(UUID.self, forKey: .addressId)
        // Use "id" if present, otherwise use address_id as the stable id (e.g. view or older DB without id)
        if let decodedId = try? c.decode(UUID.self, forKey: .id) {
            id = decodedId
        } else {
            id = addressId
        }
        campaignId = try c.decode(UUID.self, forKey: .campaignId)
        status = try c.decode(AddressStatus.self, forKey: .status)
        lastVisitedAt = try c.decodeIfPresent(Date.self, forKey: .lastVisitedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        visitCount = try c.decodeIfPresent(Int.self, forKey: .visitCount) ?? 0
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

