import Foundation
import CoreLocation
import Supabase


/// Reusable wrapper around SupabaseClient with common operations
struct SupabaseClientShim {
    let client: SupabaseClient
    
    init() {
        self.client = SupabaseManager.shared.client
    }
    
    /// Insert a row and return the inserted data
    func insertReturning<T: Decodable>(_ table: String, values: [String: Any]) async throws -> T {
        print("🔷 [SHIM] INSERT INTO \(table)")
        
        // More aggressive filtering of nil values
        let filteredValues = values.compactMapValues { (value: Any) -> Any? in
            // Skip nil values entirely
            if value is NSNull {
                return nil
            }
            
            // Skip empty strings for optional fields
            if let stringValue = value as? String, stringValue.isEmpty {
                return nil
            }
            
            // Skip nil optionals
            if case Optional<Any>.none = value {
                return nil
            }
            
            return value
        }
        
        print("🔷 [SHIM] Filtered values: \(filteredValues)")
        
        // Wrap values in AnyCodable
        let wrappedValues = filteredValues.mapValues { AnyCodable($0) }
        
        // EXPLICITLY SELECT ALL FIELDS including created_at and updated_at
        let response = try await client
            .from(table)
            .insert(wrappedValues)
            .select("id, title, description, scans, conversions, region, tags, created_at, updated_at, owner_id")
            .single()
            .execute()
        
        // ADD DEBUG LOGGING TO SEE WHAT'S ACTUALLY RETURNED
        print("🔷 [SHIM DEBUG] Raw response data: \(String(data: response.data, encoding: .utf8) ?? "nil")")
        
        // Use supabaseDates decoder for proper timestamp handling
        let decoder = JSONDecoder.supabaseDates
        
        return try decoder.decode(T.self, from: response.data)
    }
    
    /// Select rows with optional filters
    func select<T: Decodable>(_ table: String, columns: String = "*", filters: [(String, String)]? = nil) async throws -> [T] {
        print("🔷 [SHIM] SELECT \(columns) FROM \(table)")
        
        var query = client.from(table).select(columns)
        
        // Apply filters if provided
        if let filters = filters {
            for (column, condition) in filters {
                // Parse condition format: "eq.value", "gt.value", etc.
                let parts = condition.split(separator: ".", maxSplits: 1)
                if parts.count == 2 {
                    let op = String(parts[0])
                    let value = String(parts[1])
                    
                    switch op {
                    case "eq":
                        query = query.eq(column, value: value)
                    case "neq":
                        query = query.neq(column, value: value)
                    case "gt":
                        query = query.gt(column, value: value)
                    case "lt":
                        query = query.lt(column, value: value)
                    case "gte":
                        query = query.gte(column, value: value)
                    case "lte":
                        query = query.lte(column, value: value)
                    default:
                        print("⚠️ [SHIM] Unknown filter operator: \(op)")
                    }
                }
            }
        }
        
        let response = try await query.execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([T].self, from: response.data)
    }
    
    /// Call a Remote Procedure Call (RPC) function
    nonisolated func callRPC(_ function: String, params: [String: Any]) async throws {
        print("🔷 [SHIM] CALL RPC \(function)")
        
        // Create a simple struct for RPC params
        struct RPCParams: @unchecked Sendable, Encodable {
            let p_campaign_id: String
            let p_addresses: [[String: AnyCodable]]
            
            init(campaignId: String, addresses: [[String: Any]]) {
                self.p_campaign_id = campaignId
                self.p_addresses = addresses.map { addr in
                    // More aggressive filtering for RPC
                    let filteredAddr = addr.compactMapValues { (value: Any) -> Any? in
                        // Skip nil values entirely
                        if value is NSNull {
                            return nil
                        }
                        
                        // Skip empty strings for optional fields
                        if let stringValue = value as? String, stringValue.isEmpty {
                            return nil
                        }
                        
                        // Skip nil optionals
                        if case Optional<Any>.none = value {
                            return nil
                        }
                        
                        return value
                    }
                    return filteredAddr.mapValues { AnyCodable($0) }
                }
            }
        }
        
        // Extract campaign ID and addresses from params
        guard let campaignId = params["p_campaign_id"] as? String,
              let addresses = params["p_addresses"] as? [[String: Any]] else {
            throw SupabaseClientShimError.invalidResponse
        }
        
        let rpcParams = RPCParams(campaignId: campaignId, addresses: addresses)
        _ = try await client.rpc(function, params: rpcParams).execute()
        print("✅ [SHIM] RPC \(function) completed")
    }
    
    /// Get current authenticated user ID
    func currentUserId() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }
    
    /// Call RPC function with parameters and return raw response data (for map FeatureCollection decoding).
    func callRPCData(_ function: String, params: [String: Any]) async throws -> Data {
        print("🔷 [SHIM] CALL RPC \(function)")
        let encodableParams = params.mapValues { AnyCodable($0) }
        let response = try await client.rpc(function, params: encodableParams).execute()
        #if DEBUG
        let mapRPCs = ["rpc_get_campaign_addresses", "rpc_get_campaign_roads", "rpc_get_campaign_full_features"]
        if mapRPCs.contains(function) {
            let raw = String(data: response.data, encoding: .utf8) ?? ""
            let preview = String(raw.prefix(2048))
            print("[RPC DEBUG] \(function) raw JSON (first 2KB): \(preview)\(raw.count > 2048 ? "…" : "")")
        }
        #endif
        return response.data
    }
    
    /// Call RPC function with parameters and return decoded result
    func callRPC<T: Decodable>(_ function: String, params: [String: Any]) async throws -> T {
        print("🔷 [SHIM] CALL RPC \(function)")
        print("🔷 [SHIM] Params: \(params)")
        
        // Wrap params in AnyCodable to make them Encodable
        let encodableParams = params.mapValues { AnyCodable($0) }
        
        let response = try await client.rpc(function, params: encodableParams).execute()
        
        #if DEBUG
        let mapRPCs = ["rpc_get_campaign_addresses", "rpc_get_campaign_roads", "rpc_get_campaign_full_features"]
        if mapRPCs.contains(function) {
            let raw = String(data: response.data, encoding: .utf8) ?? ""
            let preview = String(raw.prefix(2048))
            print("[RPC DEBUG] \(function) raw JSON (first 2KB): \(preview)\(raw.count > 2048 ? "…" : "")")
        }
        #endif
        
        // Debug logging to see what's coming back from Supabase
        if function == "fn_addr_nearest_v2" || function == "fn_addr_same_street_v2" {
            print("[DB DEBUG] Raw JSON:", String(data: response.data, encoding: .utf8) ?? "nil")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(T.self, from: response.data)
    }
    
    // MARK: - Address Cache Methods
    
            /// Get cached addresses for a street/locality
            func getCachedAddresses(street: String, locality: String?) async throws -> [AddressCandidate] {
                print("🔷 [SHIM] Getting cached addresses for street: \(street), locality: \(locality ?? "nil")")
                
                struct RPCResult: Codable {
                    let id: UUID
                    let street: String
                    let locality: String?
                    let houseNumber: String
                    let formattedAddress: String
                    let lat: Double
                    let lon: Double
                    let source: String
                    let createdAt: Date
                    
                    enum CodingKeys: String, CodingKey {
                        case id, street, locality, source
                        case houseNumber = "house_number"
                        case formattedAddress = "formatted_address"
                        case lat, lon
                        case createdAt = "created_at"
                    }
                }
                
                // Call RPC function using our existing method
                let rows: [RPCResult] = try await callRPC("get_cached_addresses", params: [
                    "p_street": street.uppercased(),
                    "p_locality": locality ?? NSNull()
                ])
                
                print("✅ [SHIM] Found \(rows.count) cached addresses")
                
                // Convert to AddressCandidate
                return rows.map { row in
                    AddressCandidate(
                        address: row.formattedAddress,
                        coordinate: CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon),
                        distanceMeters: 0.0, // Distance not stored in cache, will be recalculated
                        number: row.houseNumber,
                        street: row.street,
                        houseKey: "\(row.houseNumber) \(row.street)".uppercased()
                    )
                }
            }
    
            /// Cache addresses for a street/locality
            func cacheAddresses(_ addresses: [AddressCandidate], street: String, locality: String?, source: String) async throws {
                print("🔷 [SHIM] Caching \(addresses.count) addresses for street: \(street), locality: \(locality ?? "nil")")
                
                // Convert addresses to JSON format for RPC
                let addressesJSON = addresses.map { candidate -> [String: Any] in
                    return [
                        "street": street.uppercased(),
                        "locality": locality ?? NSNull(),
                        "house_number": candidate.number,
                        "formatted_address": candidate.address,
                        "lat": candidate.coordinate.latitude,
                        "lon": candidate.coordinate.longitude,
                        "source": source
                    ]
                }
                
                // Call RPC function using our existing method
                let count: Int = try await callRPC("cache_addresses", params: [
                    "p_addresses": addressesJSON.map { addr in
                        addr.mapValues { value in
                            AnyCodable(value)
                        }
                    }
                ])
                
                print("✅ [SHIM] Cached \(count) addresses")
            }
}


enum SupabaseClientShimError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased wrapper for Codable values
public struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    public nonisolated func encode(to encoder: Encoder) throws {
        // Handle dictionaries using keyed container (for JSONB support)
        if let dict = value as? [String: AnyCodable] {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, val) in dict {
                try container.encode(val, forKey: DynamicCodingKey(stringValue: key))
            }
            return
        }
        
        // Handle arrays using unkeyed container
        if let array = value as? [AnyCodable] {
            var container = encoder.unkeyedContainer()
            for item in array {
                try container.encode(item)
            }
            return
        }
        
        // Handle array of dictionaries
        if let arrayOfDict = value as? [[String: AnyCodable]] {
            var container = encoder.unkeyedContainer()
            for dict in arrayOfDict {
                var dictContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self)
                for (key, val) in dict {
                    try dictContainer.encode(val, forKey: DynamicCodingKey(stringValue: key))
                }
            }
            return
        }
        
        // Handle [String] (e.g. target_building_ids for sessions insert)
        if let array = value as? [String] {
            var container = encoder.unkeyedContainer()
            for item in array {
                try container.encode(item)
            }
            return
        }
        
        // Standard encoding for primitive types using single value container
        var container = encoder.singleValueContainer()
        
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else         if let uuid = value as? UUID {
            try container.encode(uuid.uuidString)
        } else if let date = value as? Date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    // Helper for dynamic dictionary keys
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = "\(intValue)"
        }
    }
    
    public nonisolated static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality check for basic types
        if let lhsBool = lhs.value as? Bool, let rhsBool = rhs.value as? Bool {
            return lhsBool == rhsBool
        } else if let lhsInt = lhs.value as? Int, let rhsInt = rhs.value as? Int {
            return lhsInt == rhsInt
        } else if let lhsDouble = lhs.value as? Double, let rhsDouble = rhs.value as? Double {
            return lhsDouble == rhsDouble
        } else if let lhsString = lhs.value as? String, let rhsString = rhs.value as? String {
            return lhsString == rhsString
        } else if lhs.value is NSNull && rhs.value is NSNull {
            return true
        }
        return false
    }
}

