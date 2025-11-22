import Foundation
import CoreLocation

// MARK: - Task Sleep Helper

extension Task where Success == Never, Failure == Never {
    static func sleep(ms: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }
}

// MARK: - ODA Provider

/// Ontario Open Data Address provider - fast, local, free
public struct ODAProvider: AddressProvider {
    private let supabase = SupabaseClientShim()
    
    public init() {}
    
    // MARK: - Row struct for decoding (updated for fn_addr_nearest_v2)
    private struct ODARow: Codable {
        let addressId: String
        let fullAddress: String?
        let streetNo: String?
        let streetName: String?
        let city: String?
        let province: String?
        let postalCode: String?
        let distanceM: Double
        let lat: Double
        let lon: Double

        enum CodingKeys: String, CodingKey {
            case addressId = "address_id"
            case fullAddress = "full_address"
            case streetNo = "street_no"
            case streetName = "street_name"
            case city, province
            case postalCode = "postal_code"
            case distanceM = "distance_m"
            case lat, lon
        }
    }
    
    public func nearest(center: CLLocationCoordinate2D, limit: Int) async throws -> [AddressCandidate] {
        print("🏛️ [DB] Using ODA/Durham unified data for nearest addresses")
        print("🏛️ [DB] Finding \(limit) nearest addresses to \(center)")
        
        let rows: [ODARow] = try await supabase.callRPC("fn_addr_nearest_v2", params: [
            "p_lon": center.longitude,
            "p_lat": center.latitude,
            "p_limit": limit,
            "p_province": "ON"
        ])
        
        print("🏛️ [DB] Found \(rows.count) addresses from unified database")
        
        return rows.compactMap { row in
            decodeRow(row)
        }
    }
    
    public func sameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, limit: Int) async throws -> [AddressCandidate] {
        print("🏛️ [DB] Using ODA/Durham unified data for same street")
        print("🏛️ [DB] Finding \(limit) addresses on street '\(street)' in locality '\(locality ?? "any")'")
        
        let rows: [ODARow] = try await supabase.callRPC("fn_addr_same_street_v2", params: [
            "p_street": street,
            "p_city": locality ?? NSNull(),
            "p_lon": seed.longitude,
            "p_lat": seed.latitude,
            "p_limit": limit,
            "p_province": "ON"
        ])
        
        print("🏛️ [DB] Found \(rows.count) addresses on street from unified database")
        
        return rows.compactMap { row in
            decodeRow(row)
        }
    }
    
    /// Try DB once with short timeout, else throw (caller falls back to Mapbox)
    public func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int = 1200) async throws -> [AddressCandidate] {
        print("🏛️ [DB] Attempting DB fetch with \(timeoutMs)ms timeout")
        
        return try await withThrowingTaskGroup(of: [AddressCandidate].self) { group in
            group.addTask { 
                try await self.nearest(center: center, limit: limit)
            }
            group.addTask { 
                try await Task.sleep(ms: timeoutMs)
                throw NSError(domain: "DBTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database timeout after \(timeoutMs)ms"])
            }
            
            let first = try await group.next() ?? []
            group.cancelAll()
            return first
        }
    }
    
    private func decodeRow(_ row: ODARow) -> AddressCandidate? {
        let coord = CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon)
        
        // Handle optional fields safely
        let streetName = row.streetName ?? ""
        let streetNo = row.streetNo ?? ""
        let fullAddress = row.fullAddress ?? ""
        
        let streetUp = streetName.uppercased()
        let houseKey = "\(streetNo) \(streetUp)".trimmingCharacters(in: .whitespaces).uppercased()
        
        return AddressCandidate(
            address: fullAddress,
            coordinate: coord,
            distanceMeters: row.distanceM, // Now using actual distance from database
            number: streetNo,
            street: streetUp,
            houseKey: houseKey,
            source: "oda" // Mark as ODA source
        )
    }
}
