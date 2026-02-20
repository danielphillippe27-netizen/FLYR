import Foundation
import CoreLocation

// MARK: - Resolved Address

/// Represents a fully resolved address with all components
struct ResolvedAddress: Codable, Identifiable, Sendable {
    let id: UUID
    let street: String
    let formatted: String
    let locality: String
    let region: String
    let postalCode: String
    let houseNumber: String
    let streetName: String
    /// Overture GERS ID string (not a UUID)
    let gersId: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case street
        case formatted
        case locality
        case region
        case postalCode = "postal_code"
        case houseNumber = "house_number"
        case streetName = "street_name"
        case gersId = "gers_id"
    }
    
    init(id: UUID, street: String, formatted: String, locality: String, region: String, postalCode: String, houseNumber: String, streetName: String, gersId: String) {
        self.id = id
        self.street = street
        self.formatted = formatted
        self.locality = locality
        self.region = region
        self.postalCode = postalCode
        self.houseNumber = houseNumber
        self.streetName = streetName
        self.gersId = gersId
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        street = try c.decode(String.self, forKey: .street)
        formatted = try c.decode(String.self, forKey: .formatted)
        locality = try c.decode(String.self, forKey: .locality)
        region = try c.decode(String.self, forKey: .region)
        postalCode = try c.decode(String.self, forKey: .postalCode)
        houseNumber = try c.decode(String.self, forKey: .houseNumber)
        streetName = try c.decode(String.self, forKey: .streetName)
        gersId = CampaignAddressDecoding.decodeStringIfPresent(c, forKey: .gersId) ?? ""
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(street, forKey: .street)
        try c.encode(formatted, forKey: .formatted)
        try c.encode(locality, forKey: .locality)
        try c.encode(region, forKey: .region)
        try c.encode(postalCode, forKey: .postalCode)
        try c.encode(houseNumber, forKey: .houseNumber)
        try c.encode(streetName, forKey: .streetName)
        try c.encode(gersId, forKey: .gersId)
    }
    
    /// Returns a compact display address (street only)
    var displayStreet: String {
        !street.isEmpty ? street : formatted
    }
    
    /// Returns full display address with city/state
    var displayFull: String {
        var components = [displayStreet]
        if !locality.isEmpty {
            components.append(locality)
        }
        if !region.isEmpty {
            components.append(region)
        }
        if !postalCode.isEmpty {
            components.append(postalCode)
        }
        return components.joined(separator: ", ")
    }
}

// MARK: - QR Status

/// Represents QR code status for a building/address
struct QRStatus: Codable, Sendable {
    let hasFlyer: Bool
    let totalScans: Int
    let lastScannedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case hasFlyer = "has_flyer"
        case totalScans = "total_scans"
        case lastScannedAt = "last_scanned_at"
    }
    
    /// Returns true if the QR code has been scanned at least once
    var isScanned: Bool {
        totalScans > 0
    }
    
    /// Returns a human-readable status text
    var statusText: String {
        if hasFlyer {
            return isScanned ? "Scanned \(totalScans)x" : "Flyer delivered"
        }
        return "No QR code"
    }
    
    /// Returns a human-readable subtext
    var subtext: String {
        if let lastScanned = lastScannedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last: \(formatter.localizedString(for: lastScanned, relativeTo: Date()))"
        }
        if hasFlyer {
            return "Not scanned yet"
        }
        return "Generate online flyrpro.app"
    }
    
    /// Default QR status for addresses without QR codes
    static var empty: QRStatus {
        QRStatus(hasFlyer: false, totalScans: 0, lastScannedAt: nil)
    }
}

// MARK: - Building Data (Complete)

/// Complete building data including address, residents, QR status, and voice-note fields
struct BuildingData: Sendable {
    let isLoading: Bool
    let error: Error?
    /// Primary or selected address (matches preferredAddressId when provided)
    let address: ResolvedAddress?
    /// All addresses linked to this building (multiple units per building)
    let addresses: [ResolvedAddress]
    let residents: [Contact]
    let qrStatus: QRStatus
    let buildingExists: Bool
    let addressLinked: Bool
    /// Voice note / AI-derived: contact name, lead status, product interest, follow-up date, summary
    let contactName: String?
    let leadStatus: String?
    let productInterest: String?
    let followUpDate: Date?
    let aiSummary: String?
    
    /// Returns true if this building has valid address data
    var hasAddress: Bool {
        address != nil && addressLinked
    }
    
    /// Returns true when this building has more than one address (multi-address Gold/Silver)
    var isMultiAddress: Bool {
        addresses.count > 1
    }
    
    /// Returns the primary resident (first in list)
    var primaryResident: Contact? {
        residents.first
    }
    
    /// Returns true if any resident has notes
    var hasNotes: Bool {
        residents.contains { $0.notes != nil && !($0.notes?.isEmpty ?? true) }
    }
    
    /// Returns the first resident's notes if available
    var firstNotes: String? {
        residents.first(where: { $0.notes != nil && !($0.notes?.isEmpty ?? true) })?.notes
    }
    
    /// Default empty building data
    static var empty: BuildingData {
        BuildingData(
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
    }
    
    /// Loading state
    static var loading: BuildingData {
        BuildingData(
            isLoading: true,
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
    }
}

// MARK: - Cached Building Data

/// Cached building data with timestamp for TTL management
struct CachedBuildingData {
    let data: BuildingData
    let timestamp: Date
    
    /// Returns true if the cache is still valid (within TTL)
    func isValid(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) < ttl
    }
}

// MARK: - Contact Extension

extension Contact {
    /// Returns a display name for the contact
    var displayName: String {
        fullName.isEmpty ? "Unknown" : fullName
    }
    
    /// Returns true if the contact has valid contact info
    var hasContactInfo: Bool {
        !(phone?.isEmpty ?? true) || !(email?.isEmpty ?? true)
    }
}

// MARK: - Flexible decoding helpers (Supabase may return numbers/UUIDs as strings)

private enum CampaignAddressDecoding {
    static func decodeIntIfPresent<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> Int? {
        if let n = try? container.decodeIfPresent(Int.self, forKey: key) { return n }
        if let s = try? container.decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
    static func decodeUUIDIfPresent<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> UUID? {
        if let u = try? container.decodeIfPresent(UUID.self, forKey: key) { return u }
        if let s = try? container.decodeIfPresent(String.self, forKey: key), let u = UUID(uuidString: s) { return u }
        return nil
    }
    /// Decode as String (backend may return gers_id as string or number); for Overture GERS IDs use string.
    static func decodeStringIfPresent<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> String? {
        if let s = try? container.decodeIfPresent(String.self, forKey: key), !s.isEmpty { return s }
        if let n = try? container.decodeIfPresent(Int.self, forKey: key) { return String(n) }
        return nil
    }
}

// MARK: - Campaign Address Response (for Supabase queries)

/// Response model for campaign_addresses Supabase queries.
/// Uses flexible decoding so numeric/UUID fields that Supabase returns as strings still decode.
struct CampaignAddressResponse: Codable {
    let id: UUID
    let houseNumber: String?
    let streetName: String?
    let formatted: String?
    let locality: String?
    let region: String?
    let postalCode: String?
    /// Overture GERS ID string (backend may return string or UUID-shaped string)
    let gersId: String?
    let buildingGersId: String?
    let scans: Int?
    let lastScannedAt: Date?
    let qrCodeBase64: String?
    let contactName: String?
    let leadStatus: String?
    let productInterest: String?
    let followUpDate: Date?
    let rawTranscript: String?
    let aiSummary: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case houseNumber = "house_number"
        case streetName = "street_name"
        case formatted
        case locality
        case region
        case postalCode = "postal_code"
        case gersId = "gers_id"
        case buildingGersId = "building_gers_id"
        case scans
        case lastScannedAt = "last_scanned_at"
        case qrCodeBase64 = "qr_code_base64"
        case contactName = "contact_name"
        case leadStatus = "lead_status"
        case productInterest = "product_interest"
        case followUpDate = "follow_up_date"
        case rawTranscript = "raw_transcript"
        case aiSummary = "ai_summary"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        houseNumber = try c.decodeIfPresent(String.self, forKey: .houseNumber)
        streetName = try c.decodeIfPresent(String.self, forKey: .streetName)
        formatted = try c.decodeIfPresent(String.self, forKey: .formatted)
        locality = try c.decodeIfPresent(String.self, forKey: .locality)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode)
        gersId = CampaignAddressDecoding.decodeStringIfPresent(c, forKey: .gersId)
        buildingGersId = CampaignAddressDecoding.decodeStringIfPresent(c, forKey: .buildingGersId)
        scans = CampaignAddressDecoding.decodeIntIfPresent(c, forKey: .scans)
        lastScannedAt = try c.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        qrCodeBase64 = try c.decodeIfPresent(String.self, forKey: .qrCodeBase64)
        contactName = try c.decodeIfPresent(String.self, forKey: .contactName)
        leadStatus = try c.decodeIfPresent(String.self, forKey: .leadStatus)
        productInterest = try c.decodeIfPresent(String.self, forKey: .productInterest)
        followUpDate = try c.decodeIfPresent(Date.self, forKey: .followUpDate)
        rawTranscript = try c.decodeIfPresent(String.self, forKey: .rawTranscript)
        aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(houseNumber, forKey: .houseNumber)
        try c.encodeIfPresent(streetName, forKey: .streetName)
        try c.encodeIfPresent(formatted, forKey: .formatted)
        try c.encodeIfPresent(locality, forKey: .locality)
        try c.encodeIfPresent(region, forKey: .region)
        try c.encodeIfPresent(postalCode, forKey: .postalCode)
        try c.encodeIfPresent(gersId, forKey: .gersId)
        try c.encodeIfPresent(buildingGersId, forKey: .buildingGersId)
        try c.encodeIfPresent(scans, forKey: .scans)
        try c.encodeIfPresent(lastScannedAt, forKey: .lastScannedAt)
        try c.encodeIfPresent(qrCodeBase64, forKey: .qrCodeBase64)
        try c.encodeIfPresent(contactName, forKey: .contactName)
        try c.encodeIfPresent(leadStatus, forKey: .leadStatus)
        try c.encodeIfPresent(productInterest, forKey: .productInterest)
        try c.encodeIfPresent(followUpDate, forKey: .followUpDate)
        try c.encodeIfPresent(rawTranscript, forKey: .rawTranscript)
        try c.encodeIfPresent(aiSummary, forKey: .aiSummary)
    }
    
    /// Converts to ResolvedAddress
    func toResolvedAddress(fallbackGersId: String) -> ResolvedAddress {
        let house = houseNumber ?? ""
        let street = streetName ?? ""
        let combinedStreet = "\(house) \(street)".trimmingCharacters(in: .whitespaces)
        
        return ResolvedAddress(
            id: id,
            street: !combinedStreet.isEmpty ? combinedStreet : (formatted ?? "Unknown Address"),
            formatted: formatted ?? combinedStreet,
            locality: locality ?? "",
            region: region ?? "",
            postalCode: postalCode ?? "",
            houseNumber: houseNumber ?? "",
            streetName: streetName ?? "",
            gersId: gersId ?? buildingGersId ?? fallbackGersId
        )
    }
    
    /// Converts to QRStatus
    func toQRStatus() -> QRStatus {
        QRStatus(
            hasFlyer: qrCodeBase64 != nil || (scans ?? 0) > 0,
            totalScans: scans ?? 0,
            lastScannedAt: lastScannedAt
        )
    }
}

// MARK: - Building Address Link Response (for Supabase queries)

/// Response model for building_address_links with nested campaign_addresses
struct BuildingAddressLinkResponse: Codable {
    let addressId: UUID
    let campaignAddress: CampaignAddressResponse?
    
    enum CodingKeys: String, CodingKey {
        case addressId = "address_id"
        case campaignAddress = "campaign_addresses"
    }
}

// MARK: - Building Response (for Supabase queries)

/// Response model for buildings table queries (gers_id may be returned as string)
struct BuildingResponse: Codable {
    let id: UUID
    let gersId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        gersId = CampaignAddressDecoding.decodeUUIDIfPresent(c, forKey: .gersId)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(gersId, forKey: .gersId)
    }
}
