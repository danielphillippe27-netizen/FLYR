import Foundation
import Supabase

/// Service for fetching and managing building-address links
final class BuildingLinkService {
    static let shared = BuildingLinkService()
    
    private let supabaseClient: SupabaseClient
    private let baseURL: String
    
    private init() {
        self.supabaseClient = SupabaseManager.shared.client
        self.baseURL = (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
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
        print("✅ [BuildingLinkService] Fetched \(featureCollection.features.count) buildings")
        return featureCollection.features
    }
    
    // MARK: - Fetch Links (from Supabase)
    
    /// Get all building-address links for a campaign
    func fetchLinks(campaignId: String) async throws -> [BuildingAddressLink] {
        print("🔗 [BuildingLinkService] Fetching links for campaign: \(campaignId)")
        
        let links: [BuildingAddressLink] = try await supabaseClient
            .from("building_address_links")
            .select("*")
            .eq("campaign_id", value: campaignId)
            .execute()
            .value
        
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
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
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
        onUpdate: @escaping (BuildingStats) -> Void
    ) async throws -> RealtimeChannel {
        let channel = supabaseClient.realtime.channel("building-stats-\(campaignId)")
        
        await channel.on(
            "postgres_changes",
            filter: ChannelFilter(
                event: "*",
                schema: "public",
                table: "building_stats",
                filter: "campaign_id=eq.\(campaignId)"
            )
        ) { payload in
            guard let payloadDict = payload as? [String: Any],
                  let new = payloadDict["new"] as? [String: Any] else { return }
            if let gersId = new["gers_id"] as? String,
               let status = new["status"] as? String,
               let scansTotal = new["scans_total"] as? Int {
                
                let stats = BuildingStats(
                    gersId: gersId,
                    status: status,
                    scansTotal: scansTotal
                )
                onUpdate(stats)
            }
        }
        
        await channel.subscribe()
        print("📡 [BuildingLinkService] Subscribed to building stats for campaign: \(campaignId)")
        
        return channel
    }
}

// MARK: - Supporting Types

/// Response from GET /api/campaigns/[id]/buildings/[id]/addresses
private struct BuildingAddressesAPIResponse: Codable {
    let addresses: [CampaignAddressResponse]
}

enum BuildingLinkError: Error {
    case invalidURL
    case fetchFailed
    case decodingFailed
    case notAuthenticated
}
