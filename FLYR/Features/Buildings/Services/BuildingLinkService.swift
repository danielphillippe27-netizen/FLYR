import Foundation
import CoreLocation
import Supabase

/// Service for fetching and managing building-address links
final class BuildingLinkService {
    static let shared = BuildingLinkService()
    
    private let supabaseClient: SupabaseClient
    private let baseURL: String
    private let campaignRepository = CampaignRepository.shared
    private let outboxRepository = OutboxRepository.shared
    
    private init() {
        self.supabaseClient = SupabaseManager.shared.client
        let raw = (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
        // Normalize flyrpro.app → www.flyrpro.app so URLSession doesn't follow a redirect that
        // strips the Authorization header, causing 401 on the buildings snapshot endpoint.
        if let components = URLComponents(string: raw), components.host == "flyrpro.app" {
            self.baseURL = "https://www.flyrpro.app"
        } else {
            self.baseURL = raw
        }
    }
    
    // MARK: - Fetch Buildings (from S3 via API)
    
    /// Fetches building GeoJSON for a campaign from S3 snapshot
    func fetchBuildings(campaignId: String) async throws -> [BuildingFeature] {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings") else {
            throw BuildingLinkError.invalidURL
        }
        
        print("🔗 [BuildingLinkService] Fetching buildings from: \(url)")
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add auth if available
        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BuildingLinkError.fetchFailed
        }
        
        // Decode FeatureCollection
        let featureCollection = try JSONDecoder().decode(BuildingFeatureCollection.self, from: data)
        if featureCollection.features.isEmpty, let body = String(data: data, encoding: .utf8) {
            print("⚠️ [BuildingLinkService] GET buildings returned 0 features (status=200). Response preview: \(body.prefix(400))...")
        }
        print("✅ [BuildingLinkService] Fetched \(featureCollection.features.count) buildings")
        return featureCollection.features
    }
    
    // MARK: - Fetch Links (from Supabase)

    /// Get all building-address links for a campaign
    func fetchLinks(campaignId: String) async throws -> [BuildingAddressLink] {
        print("🔗 [BuildingLinkService] Fetching links for campaign: \(campaignId)")

        let rawLinks: [RawBuildingAddressLink] = try await supabaseClient
            .from("building_address_links")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value

        guard !rawLinks.isEmpty else {
            print("✅ [BuildingLinkService] Fetched 0 links")
            return []
        }

        let buildingIds = Array(Set(rawLinks.map(\.buildingId)))
        let buildingRows: [BuildingIdentityRow] = try await supabaseClient
            .from("buildings")
            .select("id, gers_id")
            .in("id", values: buildingIds)
            .execute()
            .value

        let publicIdsByRowId = Dictionary(
            uniqueKeysWithValues: buildingRows.map { row in
                (row.id.lowercased(), (row.gersId?.isEmpty == false ? row.gersId! : row.id))
            }
        )

        let links = rawLinks.map { link in
            let normalizedBuildingId =
                publicIdsByRowId[link.buildingId.lowercased()] ?? link.buildingId
            return BuildingAddressLink(
                id: link.id,
                buildingId: normalizedBuildingId,
                addressId: link.addressId,
                matchType: link.matchType,
                confidence: link.confidence,
                isMultiUnit: link.isMultiUnit,
                unitCount: link.unitCount
            )
        }

        print("✅ [BuildingLinkService] Fetched \(links.count) links")
        return links
    }
    
    /// Get link for specific building
    func fetchLinkForBuilding(campaignId: String, gersId: String) async throws -> BuildingAddressLink? {
        let links: [BuildingAddressLink] = try await supabaseClient
            .from("building_address_links")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .eq("building_id", value: gersId)
            .execute()
            .value
        
        return links.first
    }
    
    /// Get all addresses linked to a building (multiple addresses per building).
    /// Uses GET /api/campaigns/[campaignId]/buildings/[buildingId]/addresses.
    func fetchAddressesForBuilding(campaignId: String, buildingId: String) async throws -> [CampaignAddressResponse] {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings/\(buildingId)/addresses") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BuildingLinkError.fetchFailed
        }
        if httpResponse.statusCode == 404 {
            return []
        }
        guard httpResponse.statusCode == 200 else {
            throw BuildingLinkError.fetchFailed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wrapper = try decoder.decode(BuildingAddressesAPIResponse.self, from: data)
        return wrapper.addresses
    }

    // MARK: - Manual Map Shapes

    @discardableResult
    func createManualAddress(
        campaignId: String,
        input: ManualAddressCreateInput
    ) async throws -> ManualAddressCreateResponse {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses/manual") else {
            throw BuildingLinkError.invalidURL
        }

        let payload: [String: Any?] = [
            "longitude": input.coordinate.longitude,
            "latitude": input.coordinate.latitude,
            "formatted": input.formatted,
            "house_number": input.houseNumber,
            "street_name": input.streetName,
            "locality": input.locality,
            "region": input.region,
            "postal_code": input.postalCode,
            "country": input.country,
            "building_id": input.buildingId
        ]

        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
        let decoder = JSONDecoder.supabaseDates
        return try decoder.decode(ManualAddressCreateResponse.self, from: responseData)
    }

    @discardableResult
    func createManualBuilding(
        campaignId: String,
        input: ManualBuildingCreateInput
    ) async throws -> ManualBuildingCreateResponse {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings/manual") else {
            throw BuildingLinkError.invalidURL
        }

        let ring = input.polygon.map { [$0.longitude, $0.latitude] }
        let geometry: [String: Any] = [
            "type": "Polygon",
            "coordinates": [ring]
        ]
        let payload: [String: Any?] = [
            "geometry": geometry,
            "height_m": input.heightMeters,
            "units_count": input.unitsCount,
            "levels": input.levels,
            "address_ids": input.addressIds
        ]

        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        let (responseData, response) = try await authorizedDataRequest(url: url, method: "POST", body: data)
        try ensureSuccessfulResponse(response, data: responseData)
        let decoder = JSONDecoder.supabaseDates
        return try decoder.decode(ManualBuildingCreateResponse.self, from: responseData)
    }

    func deleteManualAddress(campaignId: String, addressId: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/addresses/\(addressId.uuidString)/manual") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        try ensureSuccessfulResponse(response, data: data)
    }

    func deleteManualBuilding(campaignId: String, buildingId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings/\(buildingId)/manual") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        try ensureSuccessfulResponse(response, data: data)
    }

    func deleteBuildingAndAddresses(campaignId: String, buildingId: String) async throws {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBuildingId.isEmpty else {
            throw BuildingLinkError.fetchFailed
        }

        if !NetworkMonitor.shared.isOnline {
            _ = await campaignRepository.deleteBuildingLocally(
                campaignId: campaignId,
                buildingId: normalizedBuildingId
            )
            await outboxRepository.enqueue(
                entityType: "building",
                entityId: "\(campaignId.lowercased()):\(normalizedBuildingId.lowercased())",
                operation: .deleteBuilding,
                payload: DeleteBuildingOutboxPayload(
                    campaignId: campaignId,
                    buildingId: normalizedBuildingId
                )
            )
            await OfflineSyncCoordinator.shared.refreshPendingCount()
            return
        }

        guard let url = URL(string: "\(baseURL)/api/campaigns/\(campaignId)/buildings/\(buildingId)") else {
            throw BuildingLinkError.invalidURL
        }
        let (data, response) = try await authorizedDataRequest(url: url, method: "DELETE")
        do {
            try ensureSuccessfulResponse(response, data: data)
        } catch {
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 404 || Self.responseBodyLooksLikeHTML(String(data: data, encoding: .utf8) ?? "") else {
                throw error
            }

            print("⚠️ [BuildingLinkService] Building delete API unavailable, falling back to direct Supabase cleanup")
            try await deleteBuildingAndAddressesFallback(campaignId: campaignId, buildingId: buildingId)
        }

        _ = await campaignRepository.deleteBuildingLocally(
            campaignId: campaignId,
            buildingId: normalizedBuildingId
        )
    }
    
    // MARK: - Fetch Addresses
    
    func fetchAddresses(campaignId: String) async throws -> [CampaignAddress] {
        print("🔗 [BuildingLinkService] Fetching addresses for campaign: \(campaignId)")
        
        let addresses: [CampaignAddress] = try await supabaseClient
            .from("campaign_addresses")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value
        
        print("✅ [BuildingLinkService] Fetched \(addresses.count) addresses")
        return addresses
    }
    
    // MARK: - Fetch Building Stats (for colors)
    
    func fetchBuildingStats(campaignId: String) async throws -> [BuildingStats] {
        let stats: [BuildingStats] = try await supabaseClient
            .from("building_stats")
            .select("gers_id, status, scans_total")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value
        
        return stats
    }
    
    // MARK: - Fetch Building Units (for townhouses)
    
    func fetchBuildingUnits(campaignId: String, buildingGersId: String) async throws -> [BuildingUnit] {
        let units: [BuildingUnit] = try await supabaseClient
            .from("building_units")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .eq("parent_building_id", value: buildingGersId)
            .execute()
            .value
        
        return units
    }
    
    // MARK: - Combined Fetch
    
    /// Load all campaign data needed for building display
    func loadCampaignData(campaignId: String) async throws -> CampaignBuildingData {
        print("🔄 [BuildingLinkService] Loading all campaign data...")
        
        async let buildingsTask = fetchBuildings(campaignId: campaignId)
        async let linksTask = fetchLinks(campaignId: campaignId)
        async let addressesTask = fetchAddresses(campaignId: campaignId)
        async let statsTask = fetchBuildingStats(campaignId: campaignId)
        
        let (buildings, links, addresses, stats) = try await (buildingsTask, linksTask, addressesTask, statsTask)
        
        // Create lookup dictionaries
        let linksByBuildingId = Dictionary(uniqueKeysWithValues: links.map { ($0.buildingId, $0) })
        let addressesById = Dictionary(uniqueKeysWithValues: addresses.map { ($0.id.uuidString, $0) })
        let statsByGersId = Dictionary(uniqueKeysWithValues: stats.map { ($0.gersId, $0) })
        
        // Combine into BuildingWithAddress
        let buildingsWithData: [BuildingWithAddress] = buildings.map { building in
            let gersId = building.id ?? ""
            let link = linksByBuildingId[gersId]
            let address = link.flatMap { addressesById[$0.addressId] }
            let stat = statsByGersId[gersId]
            
            return BuildingWithAddress(
                building: building,
                link: link,
                address: address,
                stats: stat
            )
        }
        
        print("✅ [BuildingLinkService] Loaded \(buildingsWithData.count) buildings with data")
        
        return CampaignBuildingData(
            buildings: buildingsWithData,
            links: links,
            addresses: addresses,
            stats: statsByGersId
        )
    }
    
    // MARK: - Real-time Subscription
    
    /// Subscribe to building stats updates for real-time color changes
    func subscribeToBuildingStats(
        campaignId: String,
        onUpdate: @escaping @Sendable (BuildingStats) -> Void
    ) async throws -> RealtimeChannelV2 {
        let channel = supabaseClient.channel("building-stats-\(campaignId)")

        let updates = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "building_stats",
            filter: .eq("campaign_id", value: campaignId)
        )

        Task {
            for await action in updates {
                let record: [String: AnyJSON]
                switch action {
                case .insert(let insert):
                    record = insert.record
                case .update(let update):
                    record = update.record
                case .delete:
                    continue
                }

                guard let gersId = record["gers_id"]?.stringValue,
                      let status = record["status"]?.stringValue else {
                    continue
                }
                let scansTotal = record["scans_total"]?.intValue
                    ?? Int(record["scans_total"]?.doubleValue ?? 0)
                onUpdate(
                    BuildingStats(
                        gersId: gersId,
                        status: status,
                        scansTotal: scansTotal
                    )
                )
            }
        }

        try await channel.subscribeWithError()
        print("📡 [BuildingLinkService] Subscribed to building stats for campaign: \(campaignId)")

        return channel
    }

    // MARK: - HTTP Helpers

    private func authorizedDataRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        return try await URLSession.shared.data(for: request)
    }

    private func ensureSuccessfulResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BuildingLinkError.fetchFailed
        }
        let statusCode = httpResponse.statusCode
        guard (200..<300).contains(statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               !apiError.error.isEmpty {
                throw ManualShapeServiceError.api(apiError.error)
            }
            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !responseText.isEmpty {
                let previewLen = 200
                let preview = String(responseText.prefix(previewLen))
                let suffix = responseText.count > previewLen ? "…" : ""
                print("⚠️ [BuildingLinkService] HTTP \(statusCode) body preview: \(preview)\(suffix)")

                if Self.responseBodyLooksLikeHTML(responseText) {
                    throw ManualShapeServiceError.api(
                        "The server returned a web page instead of data (HTTP \(statusCode)). The API may not be deployed yet, or the server URL may be wrong. Try again later or contact support."
                    )
                }

                let maxPlaintext = 400
                if responseText.count > maxPlaintext {
                    let truncated = String(responseText.prefix(maxPlaintext)) + "…"
                    throw ManualShapeServiceError.api("Request failed (HTTP \(statusCode)): \(truncated)")
                }
                throw ManualShapeServiceError.api(responseText)
            }
            throw BuildingLinkError.fetchFailed
        }
    }

    private func deleteBuildingAndAddressesFallback(campaignId: String, buildingId: String) async throws {
        guard (try? await supabaseClient.auth.session) != nil else {
            throw BuildingLinkError.notAuthenticated
        }

        let resolvedBuilding = try await resolveBuildingIdentity(buildingId: buildingId)
        let publicBuildingId = (resolvedBuilding?.gersId?.isEmpty == false ? resolvedBuilding?.gersId : resolvedBuilding?.id) ?? buildingId

        var linkedAddressIds: [String] = []

        if let rowId = resolvedBuilding?.id {
            let links: [RawBuildingAddressLink] = try await supabaseClient
                .from("building_address_links")
                .select("*")
                .eq("campaign_id", value: campaignId)
                .eq("building_id", value: rowId)
                .execute()
                .value

            linkedAddressIds.append(contentsOf: links.map(\.addressId))
        }

        let buildingAddresses: [FallbackAddressRow] = try await supabaseClient
            .from("campaign_addresses")
            .select("id")
            .eq("campaign_id", value: campaignId)
            .eq("building_gers_id", value: publicBuildingId)
            .execute()
            .value

        linkedAddressIds.append(contentsOf: buildingAddresses.map(\.id))
        linkedAddressIds = Array(Set(linkedAddressIds))

        do {
            try await supabaseClient
                .from("campaign_hidden_buildings")
                .upsert(
                    [
                        [
                            "campaign_id": campaignId,
                            "public_building_id": publicBuildingId
                        ]
                    ]
                )
                .execute()
        } catch {
            print("⚠️ [BuildingLinkService] Hidden building fallback skipped: \(error.localizedDescription)")
        }

        if !linkedAddressIds.isEmpty {
            try await supabaseClient
                .from("campaign_addresses")
                .delete()
                .eq("campaign_id", value: campaignId)
                .in("id", values: linkedAddressIds)
                .execute()
        }

        if let rowId = resolvedBuilding?.id {
            _ = try? await supabaseClient
                .from("building_address_links")
                .delete()
                .eq("campaign_id", value: campaignId)
                .eq("building_id", value: rowId)
                .execute()
        }

        _ = try? await supabaseClient
            .from("building_stats")
            .delete()
            .eq("campaign_id", value: campaignId)
            .eq("gers_id", value: publicBuildingId)
            .execute()

        _ = try? await supabaseClient
            .from("building_units")
            .delete()
            .eq("campaign_id", value: campaignId)
            .eq("parent_building_id", value: publicBuildingId)
            .execute()

        if let resolvedBuilding,
           resolvedBuilding.campaignId == campaignId {
            _ = try? await supabaseClient
                .from("buildings")
                .delete()
                .eq("id", value: resolvedBuilding.id)
                .execute()
        }
    }

    private func resolveBuildingIdentity(buildingId: String) async throws -> FallbackBuildingRow? {
        let normalized = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let allBuildings: [FallbackBuildingRow] = try await supabaseClient
            .from("buildings")
            .select("id, gers_id, campaign_id")
            .execute()
            .value

        return allBuildings.first { row in
            row.id.caseInsensitiveCompare(normalized) == .orderedSame ||
            row.gersId?.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    /// True when the body is almost certainly HTML (e.g. Next.js error/404 page) rather than an API JSON error.
    private static func responseBodyLooksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype html") { return true }
        if trimmed.hasPrefix("<html") { return true }
        if text.contains("/_next/static/") { return true }
        return false
    }
}

private struct RawBuildingAddressLink: Codable {
    let id: String
    let buildingId: String
    let addressId: String
    let matchType: String
    let confidence: Double
    let isMultiUnit: Bool
    let unitCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case buildingId = "building_id"
        case addressId = "address_id"
        case matchType = "match_type"
        case confidence
        case isMultiUnit = "is_multi_unit"
        case unitCount = "unit_count"
    }
}

private struct BuildingIdentityRow: Codable {
    let id: String
    let gersId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
    }
}

private struct FallbackBuildingRow: Codable {
    let id: String
    let gersId: String?
    let campaignId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
        case campaignId = "campaign_id"
    }
}

private struct FallbackAddressRow: Codable {
    let id: String
}

struct ManualAddressCreateInput {
    let coordinate: CLLocationCoordinate2D
    let formatted: String
    let houseNumber: String?
    let streetName: String?
    let locality: String?
    let region: String?
    let postalCode: String?
    let country: String?
    let buildingId: String?
}

struct ManualBuildingCreateInput {
    let polygon: [CLLocationCoordinate2D]
    let heightMeters: Double
    let unitsCount: Int
    let levels: Int
    let addressIds: [String]
}

struct ManualAddressCreateResponse: Decodable {
    let address: CampaignAddressResponse
    let linkedBuildingId: String?

    enum CodingKeys: String, CodingKey {
        case address
        case linkedBuildingId = "linked_building_id"
    }
}

struct ManualBuildingCreateResponse: Decodable {
    let building: ManualBuildingResponse
    let linkedAddressIds: [String]

    enum CodingKeys: String, CodingKey {
        case building
        case linkedAddressIds = "linked_address_ids"
    }
}

struct ManualBuildingResponse: Decodable {
    let id: String
    let rowId: String
    let source: String
    let heightMeters: Double?
    let unitsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case rowId = "row_id"
        case source
        case heightMeters = "height_m"
        case unitsCount = "units_count"
    }
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum ManualShapeServiceError: LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message):
            return message
        }
    }
}

// MARK: - Supporting Types

/// Response from GET /api/campaigns/[id]/buildings/[id]/addresses
private struct BuildingAddressesAPIResponse: Codable {
    let addresses: [CampaignAddressResponse]
}

enum BuildingLinkError: LocalizedError {
    case invalidURL
    case fetchFailed
    case decodingFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The app couldn't build the request URL."
        case .fetchFailed:
            return "The request couldn't be completed."
        case .decodingFailed:
            return "The server response couldn't be read."
        case .notAuthenticated:
            return "You need to sign in again before making this change."
        }
    }
}
