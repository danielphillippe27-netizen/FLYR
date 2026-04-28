import Foundation
import Supabase
import CoreLocation

actor FarmService {
    static let shared = FarmService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}

    private static var farmBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private func formatError(_ error: Error) -> String {
        error.localizedDescription.lowercased()
    }

    private func isMissingColumnError(_ error: Error, column: String) -> Bool {
        let message = formatError(error)
        return message.contains("could not find the '\(column)' column")
            || message.contains("column farms_with_geojson.\(column)")
            || message.contains("column \(column)")
            || message.contains("\(column) does not exist")
    }
    
    // MARK: - Fetch Farms
    
    func fetchFarms(userID: UUID) async throws -> [Farm] {
        let workspaceId = await MainActor.run { WorkspaceContext.shared.workspaceId }
        var query = client
            .from("farms_with_geojson")
            .select()

        if let workspaceId {
            query = query.or("workspace_id.eq.\(workspaceId.uuidString),and(owner_id.eq.\(userID.uuidString),workspace_id.is.null)")
        } else {
            query = query.eq("owner_id", value: userID.uuidString)
        }

        let responseData: Data
        do {
            responseData = try await query.order("created_at", ascending: false).execute().data
        } catch {
            guard workspaceId != nil, isMissingColumnError(error, column: "workspace_id") else {
                throw error
            }

            responseData = try await client
                .from("farms_with_geojson")
                .select()
                .eq("owner_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .data
        }
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRows: [FarmDBRow] = try decoder.decode([FarmDBRow].self, from: responseData)
        
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

    func fetchAddresses(farmId: UUID) async throws -> [FarmAddressViewRow] {
        let fullSelect = """
            id,
            campaign_address_id,
            farm_id,
            gers_id,
            formatted,
            postal_code,
            source,
            house_number,
            street_name,
            locality,
            region,
            latitude,
            longitude,
            visited_count,
            last_visited_at,
            last_outcome_status,
            created_at
        """
        let fallbackSelect = """
            id,
            farm_id,
            gers_id,
            formatted,
            postal_code,
            source,
            house_number,
            street_name,
            locality,
            region,
            latitude,
            longitude,
            visited_count,
            last_visited_at,
            created_at
        """

        let responseData: Data
        do {
            responseData = try await client
                .from("farm_addresses")
                .select(fullSelect)
                .eq("farm_id", value: farmId.uuidString)
                .order("street_name", ascending: true)
                .order("house_number", ascending: true)
                .order("created_at", ascending: true)
                .execute()
                .data
        } catch {
            guard isMissingColumnError(error, column: "campaign_address_id")
                || isMissingColumnError(error, column: "last_outcome_status") else {
                throw error
            }

            responseData = try await client
                .from("farm_addresses")
                .select(fallbackSelect)
                .eq("farm_id", value: farmId.uuidString)
                .order("street_name", ascending: true)
                .order("house_number", ascending: true)
                .order("created_at", ascending: true)
                .execute()
                .data
        }

        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let rows = try decoder.decode([FarmAddressDBRow].self, from: responseData)
        let linkedCampaignId = await fetchLinkedCampaignId(farmId: farmId)
        return rows.compactMap { $0.toViewRow(campaignId: linkedCampaignId) }
    }

    func fetchCycleAddressStatuses(
        farmId: UUID,
        cycleNumber: Int
    ) async throws -> [UUID: AddressStatus] {
        let select = """
            farm_address_id,
            campaign_address_id,
            status,
            occurred_at,
            updated_at,
            farm_touches!inner(cycle_number)
        """

        let response = try await client
            .from("farm_touch_addresses")
            .select(select)
            .eq("farm_id", value: farmId.uuidString)
            .eq("farm_touches.cycle_number", value: cycleNumber)
            .neq("status", value: AddressStatus.none.rawValue)
            .order("occurred_at", ascending: false)
            .order("updated_at", ascending: false)
            .execute()

        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let rows = try decoder.decode([FarmTouchAddressStatusDBRow].self, from: response.data)

        var statuses: [UUID: AddressStatus] = [:]
        for row in rows {
            guard statuses[row.mapAddressId] == nil else { continue }
            statuses[row.mapAddressId] = row.resolvedStatus
        }

        return statuses
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
        var polygonGeoJSON: String? = nil
        if let polygon = polygon, !polygon.isEmpty {
            let coordinates = polygon.map { [$0.longitude, $0.latitude] }
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

        if let polygonGeoJSON {
            do {
                return try await createFarmViaBackend(
                    name: name,
                    startDate: startDate,
                    endDate: endDate,
                    frequency: frequency,
                    polygonGeoJSON: polygonGeoJSON,
                    areaLabel: areaLabel
                )
            } catch {
                print("⚠️ [FarmService] Backend farm create failed, falling back to direct Supabase insert: \(error.localizedDescription)")
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var insertData: [String: AnyCodable] = [
            "owner_id": AnyCodable(userId.uuidString),
            "name": AnyCodable(name),
            "start_date": AnyCodable(dateFormatter.string(from: startDate)),
            "end_date": AnyCodable(dateFormatter.string(from: endDate)),
            "frequency": AnyCodable(1)
        ]
        
        if let areaLabel = areaLabel {
            insertData["area_label"] = AnyCodable(areaLabel)
        }
        if let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) {
            insertData["workspace_id"] = AnyCodable(workspaceId.uuidString)
        }
        insertData["touches_per_interval"] = AnyCodable(1)
        insertData["touches_interval"] = AnyCodable("month")
        insertData["goal_type"] = AnyCodable("homes_per_cycle")
        insertData["goal_target"] = AnyCodable(frequency)
        insertData["home_limit"] = AnyCodable(5000)
        insertData["address_count"] = AnyCodable(0)
        
        let response: [FarmDBRow] = try await client
            .from("farms")
            .insert(insertData)
            .select("id, owner_id, name, start_date, end_date, frequency, created_at, area_label")
            .execute()
            .value
        
        guard let inserted = response.first else {
            throw NSError(domain: "FarmService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create farm"])
        }
        
        if let polygonGeoJSON = polygonGeoJSON {
            try await updateFarmPolygonGeometry(farmId: inserted.id, polygonGeoJSON: polygonGeoJSON)
        }
        
        return try await fetchFarm(id: inserted.id) ?? inserted.toFarm()
    }

    private func createFarmViaBackend(
        name: String,
        startDate: Date,
        endDate: Date,
        frequency: Int,
        polygonGeoJSON: String,
        areaLabel: String?
    ) async throws -> Farm {
        let url = URL(string: "\(Self.farmBaseURL)/api/farms")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session = try? await client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var body: [String: Any] = [
            "name": name,
            "polygon": polygonGeoJSON,
            "start_date": dateFormatter.string(from: startDate),
            "end_date": dateFormatter.string(from: endDate),
            "frequency": 1,
            "touches_per_interval": 1,
            "touches_interval": "month",
            "goal_type": "homes_per_cycle",
            "goal_target": frequency,
            "home_limit": 5000
        ]
        if let areaLabel, !areaLabel.isEmpty {
            body["area_label"] = areaLabel
        }
        if let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) {
            body["workspace_id"] = workspaceId.uuidString
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "FarmService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "FarmService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: bodyString])
        }

        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRow = try decoder.decode(FarmDBRow.self, from: data)
        return dbRow.toFarm()
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

    private func fetchLinkedCampaignId(farmId: UUID) async -> UUID? {
        struct LinkedCampaignRow: Decodable {
            let linkedCampaignId: UUID?

            enum CodingKeys: String, CodingKey {
                case linkedCampaignId = "linked_campaign_id"
            }
        }

        do {
            let response = try await client
                .from("farms")
                .select("linked_campaign_id")
                .eq("id", value: farmId.uuidString)
                .single()
                .execute()

            let row = try JSONDecoder().decode(LinkedCampaignRow.self, from: response.data)
            return row.linkedCampaignId
        } catch {
            guard !isMissingColumnError(error, column: "linked_campaign_id") else {
                return nil
            }
            print("⚠️ [FarmService] Failed to load linked campaign for farm \(farmId.uuidString): \(error)")
            return nil
        }
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
