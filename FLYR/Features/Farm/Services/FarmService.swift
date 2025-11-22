import Foundation
import Supabase
import CoreLocation

actor FarmService {
    static let shared = FarmService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch Farms
    
    func fetchFarms(userID: UUID) async throws -> [Farm] {
        // Use view that includes GeoJSON polygon
        let response = try await client
            .from("farms_with_geojson")
            .select()
            .eq("owner_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRows: [FarmDBRow] = try decoder.decode([FarmDBRow].self, from: response.data)
        
        return dbRows.map { $0.toFarm() }
    }
    
    func fetchFarm(id: UUID) async throws -> Farm? {
        let response = try await client
            .from("farms_with_geojson")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRow: FarmDBRow = try decoder.decode(FarmDBRow.self, from: response.data)
        
        return dbRow.toFarm()
    }
    
    // MARK: - Create Farm
    
    func createFarm(
        name: String,
        userId: UUID,
        startDate: Date,
        endDate: Date,
        frequency: Int,
        polygon: [CLLocationCoordinate2D]?,
        areaLabel: String? = nil
    ) async throws -> Farm {
        // Convert polygon coordinates to PostGIS geometry
        var polygonGeoJSON: String? = nil
        if let polygon = polygon, !polygon.isEmpty {
            // Create GeoJSON Polygon
            let coordinates = polygon.map { [$0.longitude, $0.latitude] }
            // Close the polygon if not already closed
            let closedCoords = coordinates.first == coordinates.last ? coordinates : coordinates + [coordinates.first!]
            let geoJSON: [String: Any] = [
                "type": "Polygon",
                "coordinates": [closedCoords]
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: geoJSON),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                polygonGeoJSON = jsonString
            }
        }
        
        // Format dates as date-only strings
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var insertData: [String: AnyCodable] = [
            "owner_id": AnyCodable(userId.uuidString),
            "name": AnyCodable(name),
            "start_date": AnyCodable(dateFormatter.string(from: startDate)),
            "end_date": AnyCodable(dateFormatter.string(from: endDate)),
            "frequency": AnyCodable(frequency)
        ]
        
        if let areaLabel = areaLabel {
            insertData["area_label"] = AnyCodable(areaLabel)
        }
        
        // First insert without polygon (we'll update it separately via RPC)
        let response: [FarmDBRow] = try await client
            .from("farms")
            .insert(insertData)
            .select("id, owner_id, name, start_date, end_date, frequency, created_at, area_label")
            .execute()
            .value
        
        guard let inserted = response.first else {
            throw NSError(domain: "FarmService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create farm"])
        }
        
        // If we have a polygon, update it using RPC to convert GeoJSON to PostGIS geometry
        if let polygonGeoJSON = polygonGeoJSON {
            try await updateFarmPolygonGeometry(farmId: inserted.id, polygonGeoJSON: polygonGeoJSON)
        }
        
        // Fetch the complete farm with polygon
        return try await fetchFarm(id: inserted.id) ?? inserted.toFarm()
    }
    
    // MARK: - Update Farm
    
    func updateFarm(_ farm: Farm) async throws -> Farm {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var updateData: [String: AnyCodable] = [
            "name": AnyCodable(farm.name),
            "start_date": AnyCodable(dateFormatter.string(from: farm.startDate)),
            "end_date": AnyCodable(dateFormatter.string(from: farm.endDate)),
            "frequency": AnyCodable(farm.frequency)
        ]
        
        if let areaLabel = farm.areaLabel {
            updateData["area_label"] = AnyCodable(areaLabel)
        }
        
        let response: [FarmDBRow] = try await client
            .from("farms")
            .update(updateData)
            .eq("id", value: farm.id)
            .select("id, owner_id, name, start_date, end_date, frequency, created_at, area_label")
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update farm"])
        }
        
        // Fetch complete farm with polygon from view
        return try await fetchFarm(id: farm.id) ?? updated.toFarm()
    }
    
    private func updateFarmPolygonGeometry(farmId: UUID, polygonGeoJSON: String) async throws {
        // Use RPC function to update polygon geometry
        // This requires a database function - we'll create it in a migration
        // For now, use direct SQL update via RPC
        struct UpdatePolygonParams: Encodable {
            let p_farm_id: String
            let p_polygon_geojson: String
        }
        
        let params = UpdatePolygonParams(
            p_farm_id: farmId.uuidString,
            p_polygon_geojson: polygonGeoJSON
        )
        
        // Call RPC function to update polygon
        // Note: This function needs to be created in the database
        _ = try await client.rpc("update_farm_polygon", params: params).execute()
    }
    
    // MARK: - Delete Farm
    
    func deleteFarm(id: UUID) async throws {
        try await client
            .from("farms")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

