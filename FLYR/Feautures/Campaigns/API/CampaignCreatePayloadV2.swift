import Foundation
import CoreLocation

public struct CampaignCreatePayloadV2: Codable, Sendable {
    public var name: String
    public var description: String          // Required for DB
    public var type: CampaignType
    public var addressSource: AddressSource
    public var addressTargetCount: Int
    public var seedQuery: String?           // Maps to DB region field
    public var seedLon: Double?
    public var seedLat: Double?
    /// Optional tags (saved to campaigns.tags in Supabase)
    public var tags: String?
    /// Array of CampaignAddress objects
    public var addressesJSON: [CampaignAddress]

    public init(
        name: String,
        description: String,
        type: CampaignType,
        addressSource: AddressSource,
        addressTargetCount: Int,
        seedQuery: String? = nil,
        seedLon: Double? = nil,
        seedLat: Double? = nil,
        tags: String? = nil,
        addressesJSON: [CampaignAddress]
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.addressSource = addressSource
        self.addressTargetCount = addressTargetCount
        self.seedQuery = seedQuery
        self.seedLon = seedLon
        self.seedLat = seedLat
        self.tags = tags
        self.addressesJSON = addressesJSON
    }
}

public enum CodableValue: Codable {
    case s(String), d(Double), i(Int), b(Bool), n
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .s(v); return }
        if let v = try? c.decode(Double.self) { self = .d(v); return }
        if let v = try? c.decode(Int.self) { self = .i(v); return }
        if let v = try? c.decode(Bool.self) { self = .b(v); return }
        self = .n
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .s(let v): try c.encode(v)
        case .d(let v): try c.encode(v)
        case .i(let v): try c.encode(v)
        case .b(let v): try c.encode(v)
        case .n: try c.encodeNil()
        }
    }
}

// Helper to map AddressCandidate → JSON record for RPC
extension AddressCandidate {
    var asJSONRecord: [String: CodableValue] {
        [
            "formatted": .s(address),
            "postal_code": .s(""),
            "lon": .d(coordinate.longitude),
            "lat": .d(coordinate.latitude)
        ]
    }
}
