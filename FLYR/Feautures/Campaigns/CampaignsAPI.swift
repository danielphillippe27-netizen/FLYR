// Features/Campaigns/CampaignsAPI.swift
import Foundation
import Supabase
import CoreLocation

// Tiny DTO for campaign creation
struct CreateCampaignDTO: Encodable {
    let title: String
    let description: String
    let region: String?
}

// Campaign address row for map display
struct CampaignAddressRow {
    let id: UUID
    let formatted: String
    let lat: Double
    let lon: Double
}

/// GeoJSON Polygon for PostGIS territory_boundary (geometry(Polygon, 4326)).
/// Matches web: { type: "Polygon", coordinates: [[[lng, lat], ...]] }; closed ring, ≥4 points.
struct GeoJSONPolygon: Codable {
    let type: String  // "Polygon"
    let coordinates: [[[Double]]]  // ring(s); first ring = outer boundary; [lng, lat]
}

/// Payload for campaigns.update(territory_boundary).
struct TerritoryBoundaryUpdate: Encodable {
    let territory_boundary: GeoJSONPolygon
}

/// Payload for campaigns.update(status).
struct CampaignStatusUpdate: Encodable {
    let status: String
}

final class CampaignsAPI {
    static let shared = CampaignsAPI()
    private let client = SupabaseManager.shared.client

    // All campaigns (optionally scoped by workspace)
    func fetchCampaigns(workspaceId: UUID? = nil) async throws -> [Campaign] {
        var query = client.from("campaigns").select()
        if let workspaceId = workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        }
        let res: PostgrestResponse<[Campaign]> = try await query.order("created_at", ascending: false).execute()
        return res.value
    }

    // Single campaign
    func fetchCampaign(id: UUID) async throws -> Campaign {
        let res: PostgrestResponse<Campaign> = try await client
            .from("campaigns")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        return res.value
    }
    
    // Fetch single campaign as CampaignDBRow (for V2 conversion)
    func fetchCampaignDBRow(id: UUID) async throws -> CampaignDBRow {
        let res: PostgrestResponse<CampaignDBRow> = try await client
            .from("campaigns")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        return res.value
    }
    
    // Campaigns for specific user
    func fetchCampaignsForUser(userId: UUID) async throws -> [Campaign] {
        let res: PostgrestResponse<[Campaign]> = try await client
            .from("campaigns")
            .select()
            .eq("owner_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        return res.value
    }
    
    // Create campaign
    func createCampaign(title: String, description: String, region: String?) async throws {
        let dto = CreateCampaignDTO(title: title, description: description, region: region)
        _ = try await client.from("campaigns").insert(dto).execute()
    }
    
    // Create Campaign V2 with payload - REAL SUPABASE INTEGRATION
    func createV2(_ payload: CampaignCreatePayloadV2) async throws -> CampaignV2 {
        print("🌐 [API DEBUG] Creating campaign V2 with payload")
        print("🌐 [API DEBUG] Campaign name: '\(payload.name)'")
        if let type = payload.type {
            print("🌐 [API DEBUG] Campaign type: \(type.rawValue) -> db: \(type.dbValue)")
        } else {
            print("🌐 [API DEBUG] Campaign type: nil (optional)")
        }
        print("🌐 [API DEBUG] Address source: \(payload.addressSource.rawValue)")
        print("🌐 [API DEBUG] Target count: \(payload.addressTargetCount)")
        print("🌐 [API DEBUG] Seed query: \(payload.seedQuery ?? "nil")")
        let seedCoordStr: String
        if let lat = payload.seedLat, let lon = payload.seedLon {
            seedCoordStr = "(\(lat), \(lon))"
        } else {
            seedCoordStr = "nil (e.g. polygon flow uses territory_boundary)"
        }
        print("🌐 [API DEBUG] Seed coordinates: \(seedCoordStr)")
        print("🌐 [API DEBUG] Addresses JSON count: \(payload.addressesJSON.count)")

        let shim = SupabaseClientShim()
        
        // 1. Get current user ID
        let userId = try await shim.currentUserId()
        print("🌐 [API DEBUG] User ID: \(userId)")
        
        // 2. Insert campaign row into campaigns table
        let sanitizedRegion = Self.sanitizeRegionForStorage(payload.seedQuery)
        let dbType = payload.type?.dbValue
        var campaignValues: [String: Any] = [
            "owner_id": userId.uuidString,
            "title": payload.name,
            "name": payload.name,
            "description": payload.description,
            "address_source": payload.addressSource.rawValue,
            "status": "draft",
            "scans": 0,
            "conversions": 0
        ]
        if let sanitizedRegion {
            campaignValues["region"] = sanitizedRegion
        }
        if let workspaceId = payload.workspaceId {
            campaignValues["workspace_id"] = workspaceId.uuidString
        }
        if let tags = payload.tags, !tags.trimmingCharacters(in: .whitespaces).isEmpty {
            campaignValues["tags"] = tags.trimmingCharacters(in: .whitespaces)
        }

        if let dbType {
            // Defensive check so we fail with a clear client-side message before DB constraint errors.
            let allowedTypes: Set<String> = [
                "flyer", "door_knock", "event", "survey", "gift", "pop_by", "open_house", "letters"
            ]
            if !allowedTypes.contains(dbType) {
                throw NSError(
                    domain: "CampaignsAPI",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported campaign type '\(dbType)'. Allowed: \(allowedTypes.sorted().joined(separator: ", "))"]
                )
            }
            campaignValues["type"] = dbType
        }
        
        print("🌐 [API DEBUG] Inserting campaign into DB...")
        let dbRow: CampaignDBRow
        do {
            dbRow = try await shim.insertReturning("campaigns", values: campaignValues)
        } catch {
            print("❌ [API DEBUG] Campaign insert failed: \(error)")
            throw error
        }
        print("✅ [API DEBUG] Campaign inserted with ID: \(dbRow.id)")
        
        // 3. Bulk insert addresses via RPC
        if !payload.addressesJSON.isEmpty {
            print("🌐 [API DEBUG] Inserting \(payload.addressesJSON.count) addresses via RPC...")
            let addressesJSON = payload.addressesJSON.map { $0.toDBJSON() }
            let params: [String: Any] = [
                "p_campaign_id": dbRow.id.uuidString,
                "p_addresses": addressesJSON
            ]
            
            try await shim.callRPC("add_campaign_addresses", params: params)
            print("✅ [API DEBUG] Addresses inserted successfully")
        }
        
        // 4. Return CampaignV2 model
        let campaign = CampaignV2(
            id: dbRow.id,
            name: dbRow.title,
            type: payload.type ?? .flyer,
            addressSource: payload.addressSource,
            addresses: payload.addressesJSON,
            totalFlyers: payload.addressesJSON.count, // Use addresses count instead of DB field
            scans: dbRow.scans,
            conversions: dbRow.conversions,
            createdAt: dbRow.createdAt,
            status: .draft,
            seedQuery: dbRow.region
        )
        
        print("✅ [API DEBUG] Campaign creation completed")
        return campaign
    }

    /// Defensive guard so malformed UI labels never pollute campaigns.region
    /// (e.g. "Polygon (9 points)" from map drawing UI).
    private static func sanitizeRegionForStorage(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.hasPrefix("polygon (") && lower.hasSuffix(" points)") {
            return nil
        }
        return raw
    }
    
    // Create Campaign V2 (legacy draft method)
    func createV2(_ draft: CampaignDraft) async throws -> CampaignV2 {
        print("🌐 [API DEBUG] Creating campaign V2 with legacy draft")
        print("🌐 [API DEBUG] Campaign name: '\(draft.name)'")
        print("🌐 [API DEBUG] Campaign type: \(draft.type.rawValue)")
        print("🌐 [API DEBUG] Address source: \(draft.addressSource.rawValue)")
        print("🌐 [API DEBUG] Address count: \(draft.addresses.count)")
        
        // For now, create in memory - in production this would save to Supabase
        let campaign = CampaignV2(
            id: UUID(),
            name: draft.name,
            type: draft.type,
            addressSource: draft.addressSource,
            addresses: draft.addresses,
            createdAt: Date(),
            status: .draft
        )
        
        print("🌐 [API DEBUG] Campaign created with ID: \(campaign.id)")
        print("🌐 [API DEBUG] Simulating network delay...")
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        print("✅ [API DEBUG] Legacy draft campaign creation completed")
        return campaign
    }
    
    // Fetch campaigns without addresses (lightweight for lists)
    func fetchCampaignsMetadata(workspaceId: UUID? = nil) async throws -> [CampaignDBRow] {
        print("🌐 [API DEBUG] Fetching campaigns metadata (no addresses)")
        var query = client.from("campaigns").select()
        if let workspaceId = workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        }
        let res: PostgrestResponse<[CampaignDBRow]> = try await query.order("created_at", ascending: false).execute()
        print("✅ [API DEBUG] Fetched \(res.value.count) campaigns metadata")
        return res.value
    }

    /// True if the workspace has at least one campaign created via Quick Start (tags contain "quick_start").
    /// Used to enforce "one free Quick Start, then Pro required".
    func hasQuickStartCampaign(workspaceId: UUID?) async throws -> Bool {
        let rows = try await fetchCampaignsMetadata(workspaceId: workspaceId)
        return rows.contains { ($0.tags ?? "").lowercased().contains("quick_start") }
    }
    
    // Fetch Campaigns V2 - REAL SUPABASE INTEGRATION
    // Fetches campaign metadata and address counts so list shows correct house count
    func fetchCampaignsV2(workspaceId: UUID? = nil) async throws -> [CampaignV2] {
        print("🌐 [API DEBUG] Fetching campaigns V2 from Supabase (metadata + address counts)")
        var query = client.from("campaigns").select()
        if let workspaceId = workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        }
        let res: PostgrestResponse<[CampaignDBRow]> = try await query.order("created_at", ascending: false).execute()
        let dbRows = res.value
        print("✅ [API DEBUG] Fetched \(dbRows.count) campaigns from DB")
        
        // 2. Fetch address counts per campaign (for house count in list)
        var addressCountByCampaignId: [UUID: Int] = [:]
        do {
            struct CampaignCountRow: Decodable {
                let campaignId: UUID
                let addressCount: Int
                enum CodingKeys: String, CodingKey {
                    case campaignId = "campaign_id"
                    case addressCount = "address_count"
                }
            }
            let countRes: PostgrestResponse<[CampaignCountRow]> = try await client
                .rpc("get_campaign_address_counts")
                .execute()
            addressCountByCampaignId = Dictionary(uniqueKeysWithValues: countRes.value.map { ($0.campaignId, $0.addressCount) })
            print("✅ [API DEBUG] Fetched address counts for \(addressCountByCampaignId.count) campaigns")
        } catch {
            print("⚠️ [API DEBUG] Could not fetch address counts (list may show 0): \(error)")
            // Continue with 0 counts so list still works
        }
        
        // 3. Convert each campaign to CampaignV2 with correct totalFlyers
        var campaigns: [CampaignV2] = []
        for dbRow in dbRows {
            let totalFlyers = addressCountByCampaignId[dbRow.id] ?? 0
            let status = dbRow.status ?? .draft
            let campaign = CampaignV2(
                id: dbRow.id,
                name: dbRow.title,
                type: .flyer, // Default - should be stored in DB
                addressSource: .closestHome, // Default - should be stored in DB
                addresses: [], // Empty - will be loaded on demand when user opens detail
                totalFlyers: totalFlyers,
                scans: dbRow.scans,
                conversions: dbRow.conversions,
                createdAt: dbRow.createdAt,
                status: status,
                seedQuery: dbRow.region
            )
            campaigns.append(campaign)
        }
        
        print("✅ [API DEBUG] Converted \(campaigns.count) campaigns to CampaignV2 with house counts")
        return campaigns
    }
    
    // MARK: - Bulk Address Operations
    
    /// Bulk add addresses to a campaign using Supabase RPC
    func bulkAddAddresses(campaignID: UUID, records: [[String: Any]]) async throws -> Int {
        guard !records.isEmpty else { return 0 }

        let shim = SupabaseClientShim()
        let params: [String: Any] = [
            "p_campaign_id": campaignID.uuidString,
            "p_addresses": records
        ]
        try await shim.callRPC("add_campaign_addresses", params: params)
        return records.count
    }
    
    // Fetch addresses for a campaign - REAL SUPABASE INTEGRATION
    func fetchAddresses(campaignId: UUID) async throws -> [CampaignAddressRow] {
        print("🌐 [API DEBUG] Fetching addresses for campaign: \(campaignId)")
        
        // Use view campaign_addresses_v which includes geom_json (pre-computed GeoJSON)
        let res: PostgrestResponse<[CampaignAddressViewRow]> = try await client
            .from("campaign_addresses_v")
            .select("id,campaign_id,formatted,postal_code,source,seq,visited,geom_json,created_at")
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        
        let dbRows = res.value
        print("✅ [API DEBUG] Fetched \(dbRows.count) addresses from DB")
        
        // Convert DB rows to CampaignAddressRow format
        let addresses = dbRows.map { row in
            CampaignAddressRow(
                id: row.id,
                formatted: row.formatted,
                lat: row.geom.coordinate.latitude,
                lon: row.geom.coordinate.longitude
            )
        }
        
        return addresses
    }
    
    // Fetch a single address by ID
    func fetchAddress(addressId: UUID) async throws -> CampaignAddressRow? {
        print("🌐 [API DEBUG] Fetching address: \(addressId)")
        
        // Use view campaign_addresses_v which includes geom_json (pre-computed GeoJSON)
        let res: PostgrestResponse<[CampaignAddressViewRow]> = try await client
            .from("campaign_addresses_v")
            .select("id,campaign_id,formatted,postal_code,source,seq,visited,geom_json,created_at")
            .eq("id", value: addressId.uuidString)
            .limit(1)
            .execute()
        
        guard let dbRow = res.value.first else {
            print("⚠️ [API DEBUG] Address not found: \(addressId)")
            return nil
        }
        
        print("✅ [API DEBUG] Fetched address from DB: \(dbRow.formatted)")
        
        return CampaignAddressRow(
            id: dbRow.id,
            formatted: dbRow.formatted,
            lat: dbRow.geom.coordinate.latitude,
            lon: dbRow.geom.coordinate.longitude
        )
    }

    // MARK: - Provision (backend Lambda/S3 → Supabase)

    /// Backend base URL for provision API (e.g. https://flyrpro.app).
    private static var provisionBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    /// Use www when host is apex to avoid redirect stripping Authorization.
    private static var provisionRequestBaseURL: String {
        guard let components = URLComponents(string: provisionBaseURL), components.host == "flyrpro.app" else {
            return provisionBaseURL
        }
        return "https://www.flyrpro.app"
    }

    /// Update campaign's territory boundary (polygon). Backend reads this when provisioning (Lambda/S3 server-side).
    func updateTerritoryBoundary(campaignId: UUID, polygonGeoJSON: String) async throws {
        guard let data = polygonGeoJSON.data(using: .utf8) else {
            throw NSError(domain: "CampaignsAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON polygon"])
        }
        let decoder = JSONDecoder()
        let polygon: GeoJSONPolygon
        do {
            polygon = try decoder.decode(GeoJSONPolygon.self, from: data)
        } catch {
            throw NSError(domain: "CampaignsAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON polygon: \(error.localizedDescription)"])
        }
        let territoryUpdate = TerritoryBoundaryUpdate(territory_boundary: polygon)
        _ = try await client
            .from("campaigns")
            .update(territoryUpdate)
            .eq("id", value: campaignId.uuidString)
            .execute()
        print("✅ [API] Updated territory_boundary for campaign \(campaignId)")
    }

    /// Update campaign status (e.g. archive).
    func updateCampaignStatus(campaignId: UUID, status: CampaignStatus) async throws {
        let payload = CampaignStatusUpdate(status: status.rawValue)
        _ = try await client
            .from("campaigns")
            .update(payload)
            .eq("id", value: campaignId.uuidString)
            .execute()
        print("✅ [API] Updated campaign \(campaignId) status to \(status.rawValue)")
    }

    /// Trigger provision: backend reads territory_boundary, calls Lambda/S3, ingests into Supabase.
    /// Returns decoded response when available so callers can inspect addresses/buildings counts.
    @discardableResult
    func provisionCampaign(campaignId: UUID) async throws -> CampaignProvisionResponse? {
        let url = URL(string: "\(Self.provisionRequestBaseURL)/api/campaigns/provision")!
        print("🌐 [API DEBUG] Provision URL: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session = try? await client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["campaign_id": campaignId.uuidString])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CampaignsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            let preview = body.count > 1000 ? String(body.prefix(1000)) + "…" : body
            print("🌐 [API DEBUG] Provision raw response (\(http.statusCode)): \(preview)")
        } else {
            print("🌐 [API DEBUG] Provision raw response (\(http.statusCode)): <empty>")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            let userMessage = Self.extractMessageFromErrorBody(data)
            let displayMessage = userMessage ?? bodyStr
            throw NSError(domain: "CampaignsAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Provision failed: \(displayMessage.prefix(300))"])
        }
        if var provisionResponse = try? JSONDecoder().decode(CampaignProvisionResponse.self, from: data) {
            if (provisionResponse.addressesSaved ?? 0) == 0 {
                let backfilled = await backfillGoldAddressesIfNeeded(campaignId: campaignId)
                if backfilled > 0 {
                    provisionResponse.addressesSaved = backfilled
                    if let existingMessage = provisionResponse.message, !existingMessage.isEmpty {
                        provisionResponse.message = "\(existingMessage) Gold backfill inserted \(backfilled) addresses."
                    } else {
                        provisionResponse.message = "Gold backfill inserted \(backfilled) addresses."
                    }
                }
            }
            print("✅ [API] Provision completed for campaign \(campaignId): addresses=\(provisionResponse.addressesSaved ?? 0), buildings=\(provisionResponse.buildingsSaved ?? 0), roads=\(provisionResponse.roadsSaved ?? 0)")
            return provisionResponse
        } else {
            print("✅ [API] Provision completed for campaign \(campaignId) (response not decoded)")
            return nil
        }
    }

    private func backfillGoldAddressesIfNeeded(campaignId: UUID) async -> Int {
        do {
            let shim = SupabaseClientShim()
            let campaignRes = try await client
                .from("campaigns")
                .select("territory_boundary,region")
                .eq("id", value: campaignId.uuidString)
                .single()
                .execute()

            guard
                let campaignJSON = try JSONSerialization.jsonObject(with: campaignRes.data) as? [String: Any],
                let territory = campaignJSON["territory_boundary"]
            else {
                print("⚠️ [API DEBUG] Gold backfill skipped: missing territory_boundary")
                return 0
            }

            let territoryData = try JSONSerialization.data(withJSONObject: territory)
            guard let polygonGeoJSON = String(data: territoryData, encoding: .utf8), !polygonGeoJSON.isEmpty else {
                print("⚠️ [API DEBUG] Gold backfill skipped: invalid polygon JSON")
                return 0
            }

            let region = (campaignJSON["region"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            var goldRows: [[String: Any]] = []

            if let region, !region.isEmpty {
                do {
                    let rawWithProvince = try await shim.callRPCData(
                        "get_gold_addresses_in_polygon_geojson",
                        params: [
                            "p_polygon_geojson": polygonGeoJSON,
                            "p_province": region
                        ]
                    )
                    goldRows = Self.parseGoldAddressRPCPayload(rawWithProvince)
                } catch {
                    print("⚠️ [API DEBUG] Gold backfill province-filtered RPC failed: \(error.localizedDescription)")
                }
            }

            if goldRows.isEmpty {
                do {
                    let rawUnfiltered = try await shim.callRPCData(
                        "get_gold_addresses_in_polygon_geojson",
                        params: ["p_polygon_geojson": polygonGeoJSON]
                    )
                    goldRows = Self.parseGoldAddressRPCPayload(rawUnfiltered)
                } catch {
                    print("⚠️ [API DEBUG] Gold backfill unfiltered RPC failed: \(error.localizedDescription)")
                }
            }

            guard !goldRows.isEmpty else {
                print("⚠️ [API DEBUG] Gold backfill found 0 rows")
                return 0
            }

            let addressesPayload = goldRows.compactMap(Self.mapGoldRowToCampaignAddressPayload)
            guard !addressesPayload.isEmpty else {
                print("⚠️ [API DEBUG] Gold backfill produced 0 valid address payload rows")
                return 0
            }

            let inserted = try await bulkAddAddresses(campaignID: campaignId, records: addressesPayload)

            print("✅ [API DEBUG] Gold backfill inserted \(inserted) addresses for campaign \(campaignId)")
            return inserted

        } catch {
            print("⚠️ [API DEBUG] Gold backfill skipped due to error: \(String(describing: error))")
            return 0
        }
    }

    private static func parseGoldAddressRPCPayload(_ data: Data) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

        if let rows = json as? [[String: Any]] {
            return rows
        }

        if let wrapper = json as? [String: Any] {
            if let nestedRows = wrapper["get_gold_addresses_in_polygon_geojson"] as? [[String: Any]] {
                return nestedRows
            }
            if wrapper["street_name"] != nil || wrapper["street_number"] != nil || wrapper["id"] != nil {
                return [wrapper]
            }
        }

        return []
    }

    private static func mapGoldRowToCampaignAddressPayload(_ row: [String: Any]) -> [String: Any]? {
        let streetNumber = (row["street_number"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let streetName = (row["street_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = (row["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let province = (row["province"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let zip = (row["zip"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = (row["country"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if let streetNumber, !streetNumber.isEmpty { parts.append(streetNumber) }
        if let streetName, !streetName.isEmpty { parts.append(streetName) }
        if let city, !city.isEmpty { parts.append(city) }
        if let province, !province.isEmpty { parts.append(province) }
        if let zip, !zip.isEmpty { parts.append(zip) }
        let formatted = parts.joined(separator: ", ")
        if formatted.isEmpty { return nil }

        var payload: [String: Any] = [
            "formatted": formatted,
            "source": "gold",
            "seq": 0,
            "visited": false
        ]

        if let lat = row["lat"] as? Double, let lon = row["lon"] as? Double {
            payload["lat"] = lat
            payload["lon"] = lon
        }

        if let geom = row["geom_geojson"] {
            if let geomString = geom as? String {
                payload["geom"] = geomString
                if payload["lat"] == nil || payload["lon"] == nil,
                   let geomData = geomString.data(using: .utf8),
                   let geo = try? JSONSerialization.jsonObject(with: geomData) as? [String: Any],
                   let coords = geo["coordinates"] as? [Double],
                   coords.count >= 2 {
                    payload["lon"] = coords[0]
                    payload["lat"] = coords[1]
                }
            } else if JSONSerialization.isValidJSONObject(geom),
                      let geomData = try? JSONSerialization.data(withJSONObject: geom),
                      let geomString = String(data: geomData, encoding: .utf8) {
                payload["geom"] = geomString
                if payload["lat"] == nil || payload["lon"] == nil,
                   let geo = geom as? [String: Any],
                   let coords = geo["coordinates"] as? [Double],
                   coords.count >= 2 {
                    payload["lon"] = coords[0]
                    payload["lat"] = coords[1]
                }
            }
        }

        guard payload["lat"] != nil, payload["lon"] != nil else {
            return nil
        }

        return payload
    }

    /// Poll campaign provision state until ready/failed/timeout so UI can gate map routing.
    func waitForProvisionReady(
        campaignId: UUID,
        timeoutSeconds: TimeInterval = 90,
        pollIntervalSeconds: TimeInterval = 2
    ) async throws -> CampaignProvisionState {
        let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
        let pollNanos = UInt64(max(0.5, pollIntervalSeconds) * 1_000_000_000)
        let start = Date()

        while Date().timeIntervalSince(start) * 1_000_000_000 < Double(timeoutNanos) {
            let state = try await fetchProvisionState(campaignId: campaignId)
            print("🧭 [API] Provision state campaign=\(campaignId) status=\(state.provisionStatus ?? "nil")")

            if state.provisionStatus == "ready" {
                return state
            }
            if state.provisionStatus == "failed" {
                return state
            }

            try await Task.sleep(nanoseconds: pollNanos)
        }

        return try await fetchProvisionState(campaignId: campaignId)
    }

    private func fetchProvisionState(campaignId: UUID) async throws -> CampaignProvisionState {
        let res: PostgrestResponse<CampaignProvisionState> = try await client
            .from("campaigns")
            .select("id,provision_status,provisioned_at,snapshot_bucket,snapshot_prefix,snapshot_buildings_url,snapshot_roads_url")
            .eq("id", value: campaignId.uuidString)
            .single()
            .execute()
        return res.value
    }

    /// Try to extract a "message" (or "error") field from error response JSON for user-facing error.
    private static func extractMessageFromErrorBody(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let msg = json["message"] as? String, !msg.isEmpty { return msg }
        if let msg = json["error"] as? String, !msg.isEmpty { return msg }
        return nil
    }
}

// MARK: - Provision response (backend contract)

/// Response from POST /api/campaigns/provision (optional decode for logging/UI).
struct CampaignProvisionResponse: Codable {
    var success: Bool?
    var addressesSaved: Int?
    var buildingsSaved: Int?
    var roadsSaved: Int?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case addressesSaved = "addresses_saved"
        case buildingsSaved = "buildings_saved"
        case roadsSaved = "roads_saved"
        case message
    }
}


struct CampaignProvisionState: Codable {
    let id: UUID
    let provisionStatus: String?
    let provisionedAt: Date?
    let snapshotBucket: String?
    let snapshotPrefix: String?
    let snapshotBuildingsURL: String?
    let snapshotRoadsURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case provisionStatus = "provision_status"
        case provisionedAt = "provisioned_at"
        case snapshotBucket = "snapshot_bucket"
        case snapshotPrefix = "snapshot_prefix"
        case snapshotBuildingsURL = "snapshot_buildings_url"
        case snapshotRoadsURL = "snapshot_roads_url"
    }
}

// MARK: - Campaign V2 API

/// Protocol for CampaignV2 API operations
protocol CampaignsV2APIType {
    func fetchCampaigns(workspaceId: UUID?) async throws -> [CampaignV2]
    func fetchCampaign(id: UUID) async throws -> CampaignV2
    func createCampaign(_ draft: CampaignV2Draft, workspaceId: UUID?) async throws -> CampaignV2
}

/// Mock implementation for CampaignV2 API
final class CampaignsV2APIMock: CampaignsV2APIType {
    private var mockCampaigns: [CampaignV2] = []
    
    func fetchCampaigns(workspaceId: UUID? = nil) async throws -> [CampaignV2] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return mockCampaigns
    }
    
    func fetchCampaign(id: UUID) async throws -> CampaignV2 {
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        guard let campaign = mockCampaigns.first(where: { $0.id == id }) else {
            throw NSError(domain: "CampaignV2API", code: 404, userInfo: [NSLocalizedDescriptionKey: "Campaign not found"])
        }
        return campaign
    }
    
    func createCampaign(_ draft: CampaignV2Draft, workspaceId: UUID? = nil) async throws -> CampaignV2 {
        try await Task.sleep(nanoseconds: 150_000_000)
        let campaign = CampaignV2(
            name: draft.name,
            type: draft.type,
            addressSource: draft.addressSource,
            addresses: draft.addresses
        )
        
        mockCampaigns.append(campaign)
        return campaign
    }
}

// MARK: - Supabase Implementation

/// Real Supabase implementation for CampaignV2 API
final class CampaignsV2APISupabase: CampaignsV2APIType {
    private let api = CampaignsAPI.shared
    
    func fetchCampaigns(workspaceId: UUID? = nil) async throws -> [CampaignV2] {
        return try await api.fetchCampaignsV2(workspaceId: workspaceId)
    }
    
    func fetchCampaign(id: UUID) async throws -> CampaignV2 {
        // Fetch campaign from DB using the shared API instance
        let dbRow = try await CampaignsAPI.shared.fetchCampaignDBRow(id: id)
        
        // Fetch addresses using the shared API instance
        let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: id)
        let campaignAddresses = addresses.map { row in
            CampaignAddress(
                address: row.formatted,
                coordinate: CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon)
            )
        }
        
        // Convert to CampaignV2 (use DB status so store.update doesn't overwrite with draft)
        return CampaignV2(
            id: dbRow.id,
            name: dbRow.title,
            type: .flyer, // Default
            addressSource: .closestHome, // Default
            addresses: campaignAddresses,
            totalFlyers: campaignAddresses.count,
            scans: dbRow.scans,
            conversions: dbRow.conversions,
            createdAt: dbRow.createdAt,
            status: dbRow.status ?? .draft,
            seedQuery: dbRow.region
        )
    }
    
    func createCampaign(_ draft: CampaignV2Draft, workspaceId: UUID? = nil) async throws -> CampaignV2 {
        let payload = CampaignCreatePayloadV2(
            name: draft.name,
            description: "",
            type: draft.type,
            addressSource: draft.addressSource,
            addressTargetCount: draft.addresses.count,
            seedQuery: nil,
            seedLon: nil,
            seedLat: nil,
            addressesJSON: draft.addresses,
            workspaceId: workspaceId
        )
        return try await api.createV2(payload)
    }
}

// MARK: - Shared API Instance

// Global shared instance for V2 API - NOW USING REAL SUPABASE API
let sharedV2API: CampaignsV2APIType = CampaignsV2APISupabase()

// MARK: - Supabase Migration Guide
/*
 MARK: - Supabase Migration Guide
 1. Create table: campaigns_v2
 2. Fields: id uuid, name text, type text, address_source text, 
    addresses text[], progress float8, created_at timestamptz
 3. Implement CampaignsV2APISupabase conforming to CampaignsV2APIType
 4. Replace CampaignsV2APIMock.shared with Supabase impl
 */
