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

struct CampaignConfidenceHotspot: Decodable {
    let geohash: String
    let centerLat: Double
    let centerLon: Double
    let campaignsCount: Int
    let avgConfidenceScore: Double
    let avgLinkedCoverage: Double
    let lowCount: Int
    let mediumCount: Int
    let highCount: Int
    let goldExactTotal: Int
    let silverTotal: Int
    let bronzeTotal: Int
    let lambdaTotal: Int
    let priorityScore: Double

    enum CodingKeys: String, CodingKey {
        case geohash
        case centerLat = "center_lat"
        case centerLon = "center_lon"
        case campaignsCount = "campaigns_count"
        case avgConfidenceScore = "avg_confidence_score"
        case avgLinkedCoverage = "avg_linked_coverage"
        case lowCount = "low_count"
        case mediumCount = "medium_count"
        case highCount = "high_count"
        case goldExactTotal = "gold_exact_total"
        case silverTotal = "silver_total"
        case bronzeTotal = "bronze_total"
        case lambdaTotal = "lambda_total"
        case priorityScore = "priority_score"
    }
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
    let region: String?
    let bbox: [Double]?
}

/// Payload for campaigns.update(status).
struct CampaignStatusUpdate: Encodable {
    let status: String
}

/// Payload for campaigns.update(name/title/type).
struct CampaignDetailsUpdate: Encodable {
    let name: String
    let title: String
    let type: String
    let description: String
}

final class CampaignsAPI {
    static let shared = CampaignsAPI()
    private static let campaignAddressPageSize = 1_000
    private let client = SupabaseManager.shared.client

    static func campaignHomeLimitMessage(from error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == "CampaignsAPI",
              let code = nsError.userInfo["code"] as? String,
              code == "campaign_home_limit_exceeded" || code == "campaign_too_large_for_app" else {
            return nil
        }
        return nsError.localizedDescription
    }

    static func campaignHomeLimitCode(from error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == "CampaignsAPI" else { return nil }
        return nsError.userInfo["code"] as? String
    }

    static func workspaceCampaignLimitMessage(from error: Error) -> String? {
        let description = (error as NSError).localizedDescription
        guard description.contains("workspace_campaign_limit_reached") ||
              description.contains("included campaign") else {
            return nil
        }
        return "This workspace already has its included campaign. Upgrade to create more campaigns."
    }

    private static func workspaceCampaignLimitError(from error: Error) -> NSError? {
        guard let message = workspaceCampaignLimitMessage(from: error) else { return nil }
        return NSError(
            domain: "CampaignsAPI",
            code: 403,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                "code": "workspace_campaign_limit_reached"
            ]
        )
    }

    private func fetchAssignedCampaignIds(workspaceId: UUID) async -> [UUID] {
        var ids = Set<UUID>()

        if let routes = try? await RouteAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceId).assignments {
            ids.formUnion(routes.filter(Self.isActiveRouteAssignment).compactMap(\.campaignId))
        } else if let legacyRoutes = try? await RoutePlansAPI.shared.fetchMyAssignedRoutes(workspaceId: workspaceId) {
            ids.formUnion(legacyRoutes.filter(Self.isActiveRouteAssignment).compactMap(\.campaignId))
        }

        if let campaignAssignments = try? await CampaignAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceId) {
            ids.formUnion(campaignAssignments.assignments.filter(\.isActive).map(\.campaignId))
        }

        return Array(ids)
    }

    private static func isActiveRouteAssignment(_ assignment: RouteAssignmentSummary) -> Bool {
        !["completed", "complete", "cancelled", "canceled", "archived", "declined"]
            .contains(assignment.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func currentUserId() async throws -> UUID {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        return try await SupabaseClientShim().currentUserId()
    }

    private func fetchOwnedCampaignRows(workspaceId: UUID) async throws -> [CampaignDBRow] {
        let userId = try await currentUserId()
        let response: PostgrestResponse<[CampaignDBRow]> = try await client
            .from("campaigns")
            .select()
            .eq("owner_id", value: userId.uuidString)
            .eq("workspace_id", value: workspaceId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        return response.value
    }

    private func fetchOwnedCampaigns(workspaceId: UUID) async throws -> [Campaign] {
        let userId = try await currentUserId()
        let response: PostgrestResponse<[Campaign]> = try await client
            .from("campaigns")
            .select()
            .eq("owner_id", value: userId.uuidString)
            .eq("workspace_id", value: workspaceId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        return response.value
    }

    private func mergeUniqueCampaigns<T>(
        primary: [T],
        secondary: [T],
        id: (T) -> UUID
    ) -> [T] {
        var seen = Set(primary.map(id))
        var merged = primary
        for item in secondary where seen.insert(id(item)).inserted {
            merged.append(item)
        }
        return merged
    }

    private func requireResolvedWorkspaceId(_ workspaceId: UUID?) async throws -> UUID {
        if let workspaceId {
            return workspaceId
        }
        if let resolvedWorkspaceId = await RoutePlansAPI.shared.existingWorkspaceIdForCurrentUser() {
            return resolvedWorkspaceId
        }
        throw NSError(
            domain: "CampaignsAPI",
            code: 400,
            userInfo: [
                NSLocalizedDescriptionKey: "Workspace context is required before loading campaigns."
            ]
        )
    }

    // All campaigns (optionally scoped by workspace)
    func fetchCampaigns(workspaceId: UUID? = nil) async throws -> [Campaign] {
        let workspaceId = try await requireResolvedWorkspaceId(workspaceId)

        let sharedIds = await fetchAssignedCampaignIds(workspaceId: workspaceId)
        let primaryCampaigns = try await fetchOwnedCampaigns(workspaceId: workspaceId)

        guard !sharedIds.isEmpty else { return primaryCampaigns }

        let secondary: PostgrestResponse<[Campaign]> = try await client
            .from("campaigns")
            .select()
            .in("id", values: sharedIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()

        return mergeUniqueCampaigns(primary: primaryCampaigns, secondary: secondary.value, id: \.id)
            .sorted { $0.createdAt > $1.createdAt }
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
        print("🌐 [API DEBUG] Ignoring client address payload count for server provision: \(payload.addressesJSON.count)")

        let shim = SupabaseClientShim()
        
        // 1. Get current user ID
        let userId = try await shim.currentUserId()
        #if DEBUG
        print("🌐 [API DEBUG] User ID: \(userId)")
        #endif
        
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
        if let mapMode = payload.mapMode {
            campaignValues["map_mode"] = mapMode
            campaignValues["standard_mode_recommended"] = mapMode == CampaignMapMode.standardPins.rawValue
        }

        if let dbType {
            // Defensive check so we fail with a clear client-side message before DB constraint errors.
            let allowedTypes = Set(CampaignType.allCases.map(\.dbValue))
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
            if let limitError = Self.workspaceCampaignLimitError(from: error) {
                throw limitError
            }
            throw error
        }
        print("✅ [API DEBUG] Campaign inserted with ID: \(dbRow.id)")
        
        if !payload.addressesJSON.isEmpty {
            print("⚠️ [API DEBUG] Client-provided addresses are ignored; backend provision owns Diamond/Bedrock lookup.")
        }
        
        // Return the campaign shell. Addresses arrive asynchronously from the backend provisioner.
        let campaign = CampaignV2(
            id: dbRow.id,
            name: dbRow.title,
            type: payload.type ?? dbRow.campaignType,
            addressSource: payload.addressSource,
            addresses: [],
            totalFlyers: 0,
            scans: dbRow.scans,
            conversions: dbRow.conversions,
            createdAt: dbRow.createdAt,
            status: .draft,
            seedQuery: dbRow.region,
            dataConfidence: dbRow.dataConfidence,
            provisionStatus: dbRow.provisionStatus,
            provisionSource: dbRow.provisionSource,
            provisionPhase: dbRow.provisionPhase,
            addressesReadyAt: dbRow.addressesReadyAt,
            mapReadyAt: dbRow.mapReadyAt,
            optimizedAt: dbRow.optimizedAt,
            hasParcels: dbRow.hasParcels,
            buildingLinkConfidence: dbRow.buildingLinkConfidence,
            mapMode: dbRow.mapMode,
            coverageScore: dbRow.coverageScore,
            dataQuality: dbRow.dataQuality,
            standardModeRecommended: dbRow.standardModeRecommended,
            dataQualityReason: dbRow.dataQualityReason
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
    
    // Create Campaign V2 from the draft compatibility shape without client address insertion.
    func createV2(_ draft: CampaignDraft) async throws -> CampaignV2 {
        print("🌐 [API DEBUG] Creating campaign V2 from draft compatibility shell")
        let payload = CampaignCreatePayloadV2(
            name: draft.name,
            description: "",
            type: draft.type,
            addressSource: draft.addressSource,
            addressTargetCount: draft.addresses.count,
            seedQuery: nil,
            seedLon: nil,
            seedLat: nil,
            addressesJSON: [],
            workspaceId: nil
        )
        return try await createV2(payload)
    }
    
    // Fetch campaigns without addresses (lightweight for lists)
    func fetchCampaignsMetadata(workspaceId: UUID? = nil) async throws -> [CampaignDBRow] {
        print("🌐 [API DEBUG] Fetching campaigns metadata (no addresses)")
        let workspaceId = try await requireResolvedWorkspaceId(workspaceId)

        let sharedIds = await fetchAssignedCampaignIds(workspaceId: workspaceId)
        var primaryCampaigns = try await fetchOwnedCampaignRows(workspaceId: workspaceId)

        primaryCampaigns = primaryCampaigns.filter { !Self.isHiddenFromCampaignLists($0) }

        guard !sharedIds.isEmpty else {
            print("✅ [API DEBUG] Fetched \(primaryCampaigns.count) campaigns metadata")
            return primaryCampaigns
        }

        let secondary: PostgrestResponse<[CampaignDBRow]> = try await client
            .from("campaigns")
            .select()
            .in("id", values: sharedIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()

        let visibleSecondary = secondary.value.filter { !Self.isHiddenFromCampaignLists($0) }
        let merged = mergeUniqueCampaigns(primary: primaryCampaigns, secondary: visibleSecondary, id: \.id)
            .sorted { $0.createdAt > $1.createdAt }
        print("✅ [API DEBUG] Fetched \(merged.count) campaigns metadata")
        return merged
    }

    /// True if the workspace has at least one campaign created via Quick Start (tags contain "quick_start").
    /// Used to enforce "one free Quick Start, then Pro required".
    func hasQuickStartCampaign(workspaceId: UUID?) async throws -> Bool {
        let rows = try await fetchCampaignsMetadataIncludingQuickStart(workspaceId: workspaceId)
        return rows.contains { ($0.tags ?? "").lowercased().contains("quick_start") }
    }

    func fetchQuickStartMapCampaign(workspaceId: UUID?) async throws -> CampaignV2? {
        let rows = try await fetchCampaignsMetadataIncludingQuickStart(workspaceId: workspaceId)
            .filter { Self.isQuickStartCampaign(tags: $0.tags) }
            .sorted { $0.createdAt > $1.createdAt }
        guard let row = rows.first else { return nil }
        return campaignV2(from: row, totalFlyers: 0)
    }

    private static func isQuickStartCampaign(tags: String?) -> Bool {
        (tags ?? "").lowercased().contains("quick_start")
    }

    private static func isHiddenFromCampaignLists(_ row: CampaignDBRow) -> Bool {
        isQuickStartCampaign(tags: row.tags) || isFarmBackedCampaign(description: row.description, tags: row.tags)
    }

    private static func isFarmBackedCampaign(description: String?, tags: String?) -> Bool {
        let normalizedTags = (tags ?? "").lowercased()
        if normalizedTags.contains("farm_backing") || normalizedTags.contains("farm_linked_campaign") {
            return true
        }

        let normalizedDescription = (description ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedDescription.hasPrefix("[farm:")
    }

    private func fetchCampaignsMetadataIncludingQuickStart(workspaceId: UUID? = nil) async throws -> [CampaignDBRow] {
        let workspaceId = try await requireResolvedWorkspaceId(workspaceId)
        let sharedIds = await fetchAssignedCampaignIds(workspaceId: workspaceId)
        let primaryCampaigns = try await fetchOwnedCampaignRows(workspaceId: workspaceId)

        guard !sharedIds.isEmpty else {
            return primaryCampaigns
        }

        let secondary: PostgrestResponse<[CampaignDBRow]> = try await client
            .from("campaigns")
            .select()
            .in("id", values: sharedIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()

        return mergeUniqueCampaigns(primary: primaryCampaigns, secondary: secondary.value, id: \.id)
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    // Fetch Campaigns V2 - REAL SUPABASE INTEGRATION
    // Fetches campaign metadata and address counts so list shows correct house count
    func fetchCampaignsV2(workspaceId: UUID? = nil) async throws -> [CampaignV2] {
        print("🌐 [API DEBUG] Fetching campaigns V2 from Supabase (metadata + address counts)")
        if OfflineFirstConfig.isEnabled && !NetworkMonitor.shared.isOnline {
            let cachedCampaigns = await CampaignRepository.shared.getCachedCampaigns()
            if !cachedCampaigns.isEmpty {
                PerfTrace.event("offline_first", "campaign_list_cache_hit", fields: [
                    "count": cachedCampaigns.count,
                    "online": NetworkMonitor.shared.isOnline
                ])
                return cachedCampaigns
            }
        }

        if !NetworkMonitor.shared.isOnline {
            let cachedCampaigns = await CampaignRepository.shared.getCachedCampaigns()
            if !cachedCampaigns.isEmpty {
                print("📴 [API DEBUG] Loaded \(cachedCampaigns.count) cached campaigns for offline list")
                return cachedCampaigns
            }
        }

        do {
            let dbRows: [CampaignDBRow]
            let workspaceId = try await requireResolvedWorkspaceId(workspaceId)
            let sharedIds = await fetchAssignedCampaignIds(workspaceId: workspaceId)
            let primaryCampaigns = try await fetchOwnedCampaignRows(workspaceId: workspaceId)

            if sharedIds.isEmpty {
                dbRows = primaryCampaigns.filter { !Self.isHiddenFromCampaignLists($0) }
            } else {
                let secondary: PostgrestResponse<[CampaignDBRow]> = try await client
                    .from("campaigns")
                    .select()
                    .in("id", values: sharedIds.map(\.uuidString))
                    .order("created_at", ascending: false)
                    .execute()
                let visiblePrimary = primaryCampaigns.filter { !Self.isHiddenFromCampaignLists($0) }
                let visibleSecondary = secondary.value.filter { !Self.isHiddenFromCampaignLists($0) }
                dbRows = mergeUniqueCampaigns(primary: visiblePrimary, secondary: visibleSecondary, id: \.id)
                    .sorted { $0.createdAt > $1.createdAt }
            }
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
                print("⚠️ [API DEBUG] Could not fetch live address counts; using cached counts: \(error)")
                let cachedCampaigns = await CampaignRepository.shared.getCachedCampaigns()
                addressCountByCampaignId = Dictionary(
                    uniqueKeysWithValues: cachedCampaigns.map { ($0.id, $0.houseCount) }
                )
                print("📴 [API DEBUG] Falling back to \(addressCountByCampaignId.count) cached campaign counts")
            }

            // 3. Convert each campaign to CampaignV2 with correct totalFlyers
            var campaigns: [CampaignV2] = []
            for dbRow in dbRows {
                let totalFlyers = addressCountByCampaignId[dbRow.id] ?? 0
                let status = dbRow.status ?? .draft
                let campaign = campaignV2(from: dbRow, totalFlyers: totalFlyers, status: status)
                campaigns.append(campaign)
            }

            await CampaignRepository.shared.upsertCampaignMetadataRows(
                dbRows,
                addressCounts: addressCountByCampaignId
            )

            print("✅ [API DEBUG] Converted \(campaigns.count) campaigns to CampaignV2 with house counts")
            return campaigns
        } catch {
            let cachedCampaigns = await CampaignRepository.shared.getCachedCampaigns()
            if !cachedCampaigns.isEmpty {
                print("⚠️ [API DEBUG] Campaign DB fetch failed, using \(cachedCampaigns.count) cached campaigns: \(error.localizedDescription) debug=\(String(describing: error))")
                return cachedCampaigns
            }
            throw error
        }
    }

    private func campaignV2(
        from dbRow: CampaignDBRow,
        totalFlyers: Int,
        status: CampaignStatus? = nil
    ) -> CampaignV2 {
        CampaignV2(
            id: dbRow.id,
            name: dbRow.title,
            type: dbRow.campaignType,
            addressSource: dbRow.addressSource,
            addresses: [],
            totalFlyers: totalFlyers,
            scans: dbRow.scans,
            conversions: dbRow.conversions,
            createdAt: dbRow.createdAt,
            status: status ?? dbRow.status ?? .draft,
            seedQuery: dbRow.region,
            dataConfidence: dbRow.dataConfidence,
            provisionStatus: dbRow.provisionStatus,
            provisionSource: dbRow.provisionSource,
            provisionPhase: dbRow.provisionPhase,
            addressesReadyAt: dbRow.addressesReadyAt,
            mapReadyAt: dbRow.mapReadyAt,
            optimizedAt: dbRow.optimizedAt,
            hasParcels: dbRow.hasParcels,
            buildingLinkConfidence: dbRow.buildingLinkConfidence,
            mapMode: dbRow.mapMode,
            coverageScore: dbRow.coverageScore,
            dataQuality: dbRow.dataQuality,
            standardModeRecommended: dbRow.standardModeRecommended,
            dataQualityReason: dbRow.dataQualityReason
        )
    }

    /// Lightweight count for the campaign list/creation flow.
    /// This intentionally avoids fetching address geometries; renderable geometry is PMTiles-first.
    func fetchCampaignAddressCount(campaignId: UUID) async throws -> Int {
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

        return countRes.value.first { $0.campaignId == campaignId }?.addressCount ?? 0
    }

    /// Single RPC: centroid (lat/lon) per campaign for map markers. Skips campaigns with no addresses.
    func fetchCampaignAddressCentroids() async throws -> [UUID: CLLocationCoordinate2D] {
        struct CentroidRow: Decodable {
            let campaignId: UUID
            let lat: Double
            let lon: Double
            enum CodingKeys: String, CodingKey {
                case campaignId = "campaign_id"
                case lat, lon
            }
        }
        let res: PostgrestResponse<[CentroidRow]> = try await client
            .rpc("get_campaign_address_centroids")
            .execute()
        return Dictionary(uniqueKeysWithValues: res.value.map {
            ($0.campaignId, CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon))
        })
    }

    /// Aggregated campaign-confidence hotspots for internal diagnostics or future admin UI.
    func fetchCampaignConfidenceHotspots(
        precision: Int = 5,
        workspaceId: UUID? = nil
    ) async throws -> [CampaignConfidenceHotspot] {
        struct CampaignConfidenceHotspotsRPCParams: Encodable {
            let p_precision: Int
            let p_workspace_id: String?
        }

        let params = CampaignConfidenceHotspotsRPCParams(
            p_precision: precision,
            p_workspace_id: workspaceId?.uuidString
        )
        let res: PostgrestResponse<[CampaignConfidenceHotspot]> = try await client
            .rpc("get_campaign_confidence_hotspots", params: params)
            .execute()
        return res.value
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

        if !NetworkMonitor.shared.isOnline {
            let cachedRows = await CampaignRepository.shared.getCachedAddressRows(campaignId: campaignId)
            if !cachedRows.isEmpty {
                print("📴 [API DEBUG] Loaded \(cachedRows.count) cached addresses for offline campaign: \(campaignId)")
                return cachedRows
            }
        }
        
        let dbRows: [CampaignAddressViewRow]
        do {
            dbRows = try await fetchAllAddressViewRows(campaignId: campaignId)
        } catch {
            let cachedRows = await CampaignRepository.shared.getCachedAddressRows(campaignId: campaignId)
            if !cachedRows.isEmpty {
                print("⚠️ [API DEBUG] Address fetch failed, using \(cachedRows.count) cached rows: \(error.localizedDescription)")
                return cachedRows
            }
            throw error
        }

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

    private func fetchAllAddressViewRows(campaignId: UUID) async throws -> [CampaignAddressViewRow] {
        var rows: [CampaignAddressViewRow] = []
        var from = 0

        while true {
            let to = from + Self.campaignAddressPageSize - 1
            let res: PostgrestResponse<[CampaignAddressViewRow]> = try await client
                .from("campaign_addresses_v")
                .select("id,campaign_id,formatted,postal_code,source,seq,visited,geom_json,created_at")
                .eq("campaign_id", value: campaignId.uuidString)
                .order("seq", ascending: true)
                .range(from: from, to: to)
                .execute()

            let page = res.value
            rows.append(contentsOf: page)
            if page.count < Self.campaignAddressPageSize {
                break
            }
            from += Self.campaignAddressPageSize
        }

        return rows
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

    // MARK: - Provision (Diamond/Bedrock backend)

    /// Backend base URL for provision API (e.g. https://wolfgrid.app).
    private static var provisionBaseURL: String {
        Config.backendAPIURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Uses the backend deployment host when the custom app domain is caught in an apex/www redirect loop.
    private static var provisionRequestBaseURL: String {
        provisionBaseURL
    }

    /// Provision does a full backend pipeline (Diamond/Bedrock + ingest + linking + routing),
    /// so give it a longer timeout than the default shared session.
    private static let provisionRequestTimeout: TimeInterval = 180
    private static let provisionResourceTimeout: TimeInterval = 300

    private static func makeProvisionSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = provisionRequestTimeout
        configuration.timeoutIntervalForResource = provisionResourceTimeout
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private static func provisionResponse(from state: CampaignProvisionState) -> CampaignProvisionResponse {
        let isReady = state.provisionStatus == .ready
        let isFailed = state.provisionStatus == .failed
        let failureMessage = state.provisionMessage ?? state.provisionError ?? "Campaign provisioning failed on the server."
        return CampaignProvisionResponse(
            success: isReady,
            addressesSaved: nil,
            buildingsSaved: nil,
            roadsCount: nil,
            roadsSaved: nil,
            message: isReady
                ? "Campaign is map-ready."
                : isFailed
                    ? failureMessage
                    : "Campaign provisioning is still in progress.",
            error: isFailed ? failureMessage : nil,
            accepted: false,
            dataConfidenceScore: nil,
            dataConfidenceLabel: nil,
            dataConfidenceReason: nil,
            dataConfidenceSummary: nil,
            provisionStatus: state.provisionStatus,
            provisionPhase: state.provisionPhase,
            provisionSource: state.provisionSource,
            mapReady: state.provisionStatus == .ready,
            optimized: state.provisionPhase?.isLinkComplete == true,
            postprocessDeferred: state.provisionPhase?.isLinkComplete != true,
            parcelEnrichmentStatus: nil,
            provisionTimings: state.provisionTimings,
            linkerPath: nil,
            warning: isFailed ? failureMessage : "Provision request timed out on the client, but the server kept working.",
            hasParcels: nil,
            buildingLinkConfidence: nil,
            mapMode: nil,
            coverageScore: state.coverageScore,
            dataQuality: state.dataQuality,
            standardModeRecommended: state.standardModeRecommended,
            dataQualityReason: state.dataQualityReason,
            code: nil,
            homeCount: nil,
            maxCampaignHomes: nil,
            maxAppHomes: nil,
            suggestedCampaigns: nil
        )
    }

    /// Update campaign's territory boundary (polygon). Backend reads this when provisioning server-side.
    func updateTerritoryBoundary(campaignId: UUID, polygonGeoJSON: String, regionCode: String? = nil) async throws {
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
        let normalizedRegion = regionCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let territoryUpdate = TerritoryBoundaryUpdate(
            territory_boundary: polygon,
            region: normalizedRegion?.isEmpty == false ? normalizedRegion : nil,
            bbox: Self.bbox(for: polygon)
        )
        _ = try await client
            .from("campaigns")
            .update(territoryUpdate)
            .eq("id", value: campaignId.uuidString)
            .execute()
        print("✅ [API] Updated territory_boundary for campaign \(campaignId)")
    }

    func enableStandardPinsMode(campaignId: UUID) async throws {
        struct StandardPinsUpdate: Encodable {
            let map_mode = CampaignMapMode.standardPins.rawValue
            let standard_mode_recommended = true
        }
        _ = try await client
            .from("campaigns")
            .update(StandardPinsUpdate())
            .eq("id", value: campaignId.uuidString)
            .execute()
    }

    static func bbox(for polygon: GeoJSONPolygon) -> [Double]? {
        let coordinates = polygon.coordinates.flatMap { $0 }
        let lons = coordinates.compactMap { $0.first }
        let lats = coordinates.compactMap { $0.count > 1 ? $0[1] : nil }
        guard let minLon = lons.min(),
              let minLat = lats.min(),
              let maxLon = lons.max(),
              let maxLat = lats.max() else {
            return nil
        }
        return [minLon, minLat, maxLon, maxLat]
    }

    /// Update the user-facing campaign details after the territory-first create flow starts.
    func updateCampaignDetails(campaignId: UUID, name: String, type: CampaignType, description: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "CampaignsAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Campaign name is required"])
        }

        let allowedTypes = Set(CampaignType.allCases.map(\.dbValue))
        guard allowedTypes.contains(type.dbValue) else {
            throw NSError(domain: "CampaignsAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported campaign type '\(type.dbValue)'"])
        }

        let detailsUpdate = CampaignDetailsUpdate(
            name: trimmedName,
            title: trimmedName,
            type: type.dbValue,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        _ = try await client
            .from("campaigns")
            .update(detailsUpdate)
            .eq("id", value: campaignId.uuidString)
            .execute()
        print("✅ [API] Updated campaign \(campaignId) details")
    }

    /// Fetch the campaign's territory boundary (same polygon used for addresses/buildings).
    /// Returns nil if the campaign has no boundary or it fails to decode.
    func fetchTerritoryBoundary(campaignId: UUID) async -> [CLLocationCoordinate2D]? {
        struct Row: Decodable {
            let territory_boundary: GeoJSONPolygon?
        }
        do {
            let res = try await client
                .from("campaigns")
                .select("territory_boundary")
                .eq("id", value: campaignId.uuidString)
                .single()
                .execute()
            let row = try JSONDecoder().decode(Row.self, from: res.data)
            guard let polygon = row.territory_boundary else { return nil }
            let ring = polygon.coordinates.first ?? []
            return ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        } catch {
            return nil
        }
    }

    /// Update campaign status (e.g. archive).
    func updateCampaignStatus(campaignId: UUID, status: CampaignStatus) async throws {
        let payload = CampaignStatusUpdate(status: status.rawValue)
        _ = try await client
            .from("campaigns")
            .update(payload)
            .eq("id", value: campaignId.uuidString)
            .execute()

        try await verifyCampaignStatus(campaignId: campaignId, expectedStatus: status)
        await CampaignRepository.shared.updateCachedCampaignStatus(campaignId: campaignId, status: status)
        print("✅ [API] Updated campaign \(campaignId) status to \(status.rawValue)")
    }

    func deleteCampaign(campaignId: UUID) async throws {
        try await deleteCampaignThroughBackend(campaignId: campaignId)
        await CampaignRepository.shared.removeCachedCampaign(campaignId: campaignId)
        print("✅ [API] Deleted campaign \(campaignId)")
    }

    func deleteCampaigns(campaignIDs: [UUID]) async throws {
        let uniqueIDs = Array(Set(campaignIDs))
        guard !uniqueIDs.isEmpty else { return }

        for campaignID in uniqueIDs {
            try await deleteCampaign(campaignId: campaignID)
        }
        print("✅ [API] Deleted \(uniqueIDs.count) campaign(s)")
    }

    private func deleteCampaignThroughBackend(campaignId: UUID) async throws {
        let url = Config.backendAPIURL
            .appendingPathComponent("api")
            .appendingPathComponent("campaigns")
            .appendingPathComponent(campaignId.uuidString)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = try await client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "CampaignsAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Campaign deletion did not receive a valid server response."]
            )
        }

        let serverMessage = Self.extractMessageFromErrorBody(data)
        // A confirmed missing row already satisfies the requested end state and can leave local caches.
        if http.statusCode == 404, serverMessage == "Campaign not found" {
            return
        }

        guard (200...299).contains(http.statusCode) else {
            let message = serverMessage ?? "Campaign could not be deleted. Please try again."
            throw NSError(
                domain: "CampaignsAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private struct CampaignMutationCheckRow: Decodable {
        let id: UUID
        let status: CampaignStatus?
    }

    private func verifyCampaignStatus(campaignId: UUID, expectedStatus: CampaignStatus) async throws {
        let response: PostgrestResponse<[CampaignMutationCheckRow]> = try await client
            .from("campaigns")
            .select("id,status")
            .eq("id", value: campaignId.uuidString)
            .limit(1)
            .execute()

        guard response.value.first?.status?.rawValue == expectedStatus.rawValue else {
            throw NSError(
                domain: "CampaignsAPI",
                code: 409,
                userInfo: [
                    NSLocalizedDescriptionKey: "Campaign status was not updated. You may not have permission to modify this campaign."
                ]
            )
        }
    }

    /// Trigger provision: backend reads territory_boundary and resolves Diamond first, then Bedrock S3.
    /// Returns decoded response when available so callers can inspect addresses/buildings counts.
    @discardableResult
    func provisionCampaign(
        campaignId: UUID,
        waitForLinker: Bool = false,
        waitUntilReady: Bool = true
    ) async throws -> CampaignProvisionResponse? {
        let trace = PerfTrace.begin("campaign_create", "api_provision_campaign", fields: [
            "campaign": campaignId.uuidString,
            "waitForLinker": waitForLinker,
            "waitUntilReady": waitUntilReady
        ])
        let url = URL(string: "\(Self.provisionRequestBaseURL)/api/campaigns/provision")!
        print("🌐 [API DEBUG] Provision URL: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.provisionRequestTimeout
        if let session = try? await client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "campaign_id": campaignId.uuidString
        ]
        if waitForLinker {
            body["wait_for_linker"] = true
            body["require_linked_homes"] = true
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.makeProvisionSession().data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                print("⚠️ [API DEBUG] Provision request timed out after \(Self.provisionRequestTimeout)s; polling campaign status...")
                let state = try await waitForProvisionReady(
                    campaignId: campaignId,
                    requireOptimized: waitForLinker,
                    timeoutSeconds: Self.provisionResourceTimeout,
                    pollIntervalSeconds: 2
                )
                if state.provisionStatus == .ready {
                    print("✅ [API DEBUG] Provision completed server-side after client timeout for campaign \(campaignId)")
                    trace.end(status: "timeout_then_ready", fields: [
                        "status": state.provisionStatus?.rawValue ?? "nil",
                        "phase": state.provisionPhase?.rawValue ?? "nil"
                    ])
                    return Self.provisionResponse(from: state)
                }
                if state.provisionStatus == .failed {
                    trace.end(status: "timeout_then_failed", fields: [
                        "status": state.provisionStatus?.rawValue ?? "nil",
                        "phase": state.provisionPhase?.rawValue ?? "nil"
                    ])
                    throw NSError(
                        domain: "CampaignsAPI",
                        code: NSURLErrorTimedOut,
                        userInfo: [NSLocalizedDescriptionKey: "Provision timed out and later failed on the server."]
                    )
                }
                print("⚠️ [API DEBUG] Provision still not ready after timeout; last status=\(state.provisionStatus?.rawValue ?? "unknown"), phase=\(state.provisionPhase?.rawValue ?? "unknown")")
            }
            trace.end(status: "network_error", fields: [
                "error": error.localizedDescription
            ])
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            trace.end(status: "invalid_response")
            throw NSError(domain: "CampaignsAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            let preview = body.count > 1000 ? String(body.prefix(1000)) + "…" : body
            print("🌐 [API DEBUG] Provision raw response (\(http.statusCode)): \(preview)")
        } else {
            print("🌐 [API DEBUG] Provision raw response (\(http.statusCode)): <empty>")
        }
        guard (200...299).contains(http.statusCode) else {
            if let provisionErr = try? JSONDecoder().decode(CampaignProvisionResponse.self, from: data) {
                let msg = provisionErr.error
                    ?? provisionErr.message
                    ?? "Provisioning did not meet readiness requirements (e.g. addresses or map roads)."
                trace.end(status: "server_error", fields: [
                    "http": http.statusCode,
                    "error": msg
                ])
                var userInfo: [String: Any] = [NSLocalizedDescriptionKey: msg]
                if let code = provisionErr.code {
                    userInfo["code"] = code
                }
                if let homeCount = provisionErr.homeCount {
                    userInfo["home_count"] = homeCount
                }
                if let maxCampaignHomes = provisionErr.maxCampaignHomes {
                    userInfo["max_campaign_homes"] = maxCampaignHomes
                }
                if let maxAppHomes = provisionErr.maxAppHomes {
                    userInfo["max_app_homes"] = maxAppHomes
                }
                if let suggestedCampaigns = provisionErr.suggestedCampaigns {
                    userInfo["suggested_campaigns"] = suggestedCampaigns
                }
                throw NSError(domain: "CampaignsAPI", code: http.statusCode, userInfo: userInfo)
            }
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            let userMessage = Self.extractMessageFromErrorBody(data)
            let displayMessage = userMessage ?? bodyStr
            trace.end(status: "server_error", fields: [
                "http": http.statusCode,
                "error": String(displayMessage.prefix(160))
            ])
            throw NSError(domain: "CampaignsAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: String(displayMessage.prefix(300))])
        }
        if let provisionResponse = try? JSONDecoder().decode(CampaignProvisionResponse.self, from: data) {
            if provisionResponse.accepted == true || provisionResponse.provisionStatus == .pending {
                guard waitUntilReady else {
                    print("🧭 [API] Provision accepted for campaign \(campaignId); server will finish in the background.")
                    trace.end(status: "accepted", fields: [
                        "http": http.statusCode,
                        "status": provisionResponse.provisionStatus?.rawValue ?? "nil",
                        "phase": provisionResponse.provisionPhase?.rawValue ?? "nil"
                    ])
                    return provisionResponse
                }
                print("🧭 [API] Provision accepted for campaign \(campaignId); polling until ready or failed...")
                let state = try await waitForProvisionReady(
                    campaignId: campaignId,
                    requireOptimized: waitForLinker,
                    timeoutSeconds: Self.provisionResourceTimeout,
                    pollIntervalSeconds: 2
                )
                trace.end(status: "accepted_then_polled", fields: [
                    "http": http.statusCode,
                    "status": state.provisionStatus?.rawValue ?? "nil",
                    "phase": state.provisionPhase?.rawValue ?? "nil"
                ])
                return Self.provisionResponse(from: state)
            }
            if waitForLinker,
               provisionResponse.provisionPhase?.isLinkComplete != true || provisionResponse.postprocessDeferred == true {
                print("🧭 [API] Waiting for campaign linker to finish before opening campaign \(campaignId)...")
                let state = try await waitForProvisionReady(
                    campaignId: campaignId,
                    requireOptimized: true,
                    timeoutSeconds: Self.provisionResourceTimeout,
                    pollIntervalSeconds: 2
                )
                trace.end(status: "waited_for_linker", fields: [
                    "http": http.statusCode,
                    "status": state.provisionStatus?.rawValue ?? "nil",
                    "phase": state.provisionPhase?.rawValue ?? "nil"
                ])
                return Self.provisionResponse(from: state)
            }
            if provisionResponse.provisionSource == .diamond {
                print("✅ [API] Provision resolved through Diamond")
            }
            let roadsLogged = provisionResponse.roadsCount ?? provisionResponse.roadsSaved ?? 0
            print("✅ [API] Provision completed for campaign \(campaignId): addresses=\(provisionResponse.addressesSaved ?? 0), buildings=\(provisionResponse.buildingsSaved ?? 0), roads=\(roadsLogged)")
            trace.end(status: "completed", fields: [
                "http": http.statusCode,
                "status": provisionResponse.provisionStatus?.rawValue ?? "nil",
                "phase": provisionResponse.provisionPhase?.rawValue ?? "nil",
                "addresses": provisionResponse.addressesSaved ?? 0,
                "buildings": provisionResponse.buildingsSaved ?? 0,
                "roads": roadsLogged
            ])
            return provisionResponse
        } else {
            print("✅ [API] Provision completed for campaign \(campaignId) (response not decoded)")
            trace.end(status: "completed_undecoded", fields: [
                "http": http.statusCode
            ])
            return nil
        }
    }

    /// Poll campaign provision state until ready/failed/timeout so UI can gate map routing.
    func waitForProvisionReady(
        campaignId: UUID,
        requireOptimized: Bool = false,
        returnWhenMapUsable: Bool = false,
        timeoutSeconds: TimeInterval = 90,
        pollIntervalSeconds: TimeInterval = 2,
        onProgress: ((CampaignProvisionState) async -> Void)? = nil
    ) async throws -> CampaignProvisionState {
        let trace = PerfTrace.begin("campaign_create", "api_wait_for_provision_ready", fields: [
            "campaign": campaignId.uuidString,
            "requireOptimized": requireOptimized,
            "timeoutSeconds": Int(timeoutSeconds),
            "pollIntervalSeconds": pollIntervalSeconds
        ])
        let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
        let pollNanos = UInt64(max(0.5, pollIntervalSeconds) * 1_000_000_000)
        let start = Date()
        var pollCount = 0

        while Date().timeIntervalSince(start) * 1_000_000_000 < Double(timeoutNanos) {
            let state = try await fetchProvisionState(campaignId: campaignId)
            pollCount += 1
            await onProgress?(state)
            let failureReason = state.provisionMessage ?? state.provisionError
            print("🧭 [API] Provision state campaign=\(campaignId) status=\(state.provisionStatus?.rawValue ?? "nil") phase=\(state.provisionPhase?.rawValue ?? "nil")\(failureReason.map { " reason=\($0)" } ?? "")")
            PerfTrace.event("campaign_create", "api_provision_poll", fields: [
                "campaign": campaignId.uuidString,
                "poll": pollCount,
                "status": state.provisionStatus?.rawValue ?? "nil",
                "phase": state.provisionPhase?.rawValue ?? "nil"
            ])

            let mapUsable = state.provisionStatus == .ready || state.provisionPhase?.isMapUsable == true
            if returnWhenMapUsable && !requireOptimized && mapUsable {
                trace.end(status: "map_usable", fields: [
                    "polls": pollCount,
                    "status": state.provisionStatus?.rawValue ?? "nil",
                    "phase": state.provisionPhase?.rawValue ?? "nil"
                ])
                return state
            }

            if state.provisionStatus == .ready && (!requireOptimized || state.provisionPhase?.isLinkComplete == true) {
                trace.end(status: "ready", fields: [
                    "polls": pollCount,
                    "phase": state.provisionPhase?.rawValue ?? "nil"
                ])
                return state
            }
            if state.provisionStatus == .failed {
                trace.end(status: "failed", fields: [
                    "polls": pollCount,
                    "phase": state.provisionPhase?.rawValue ?? "nil",
                    "reason": failureReason ?? "nil"
                ])
                return state
            }

            try await Task.sleep(nanoseconds: pollNanos)
        }

        let state = try await fetchProvisionState(campaignId: campaignId)
        await onProgress?(state)
        trace.end(status: "timeout_return_last_state", fields: [
            "polls": pollCount,
            "status": state.provisionStatus?.rawValue ?? "nil",
            "phase": state.provisionPhase?.rawValue ?? "nil"
        ])
        return state
    }

    func fetchProvisionState(campaignId: UUID) async throws -> CampaignProvisionState {
        let res: PostgrestResponse<[CampaignProvisionState]> = try await client
            .from("campaigns")
            .select("id,provision_status,provision_source,provision_phase,provisioned_at,addresses_ready_at,map_ready_at,optimized_at,snapshot_bucket,snapshot_prefix,snapshot_buildings_url,snapshot_roads_url,address_source,coverage_score,data_quality,standard_mode_recommended,data_quality_reason,provision_timings,provision_error,provision_message")
            .eq("id", value: campaignId.uuidString)
            .limit(1)
            .execute()
        guard let state = res.value.first else {
            throw NSError(
                domain: "CampaignsAPI",
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey: "Campaign provisioning state was not found."
                ]
            )
        }
        return state
    }

    /// Row used to gate session start on campaign provisioning only.
    struct CampaignSessionGateRow: Codable {
        let addressSource: String?
        let provisionStatus: String?

        enum CodingKeys: String, CodingKey {
            case addressSource = "address_source"
            case provisionStatus = "provision_status"
        }
    }

    func fetchCampaignSessionGateRow(campaignId: UUID) async throws -> CampaignSessionGateRow {
        let res: PostgrestResponse<CampaignSessionGateRow> = try await client
            .from("campaigns")
            .select("address_source,provision_status")
            .eq("id", value: campaignId.uuidString)
            .single()
            .execute()
        return res.value
    }

    /// `nil` = allowed to start session; non-nil = user-facing reason to block.
    func sessionStartBlockReason(campaignId: UUID) async -> String? {
        if OfflineFirstConfig.isEnabled {
            let campaignIdString = campaignId.uuidString
            let downloadState = await CampaignRepository.shared.getDownloadState(campaignId: campaignIdString)
            let readiness = await CampaignDownloadService.shared.readiness(for: campaignIdString)
            let mapReadiness = await CampaignDownloadService.shared.mapReadiness(for: campaignIdString)
            let hasCachedBundle = await CampaignRepository.shared.getCampaignMapBundle(campaignId: campaignIdString) != nil
            if downloadState?.isAvailableOffline == true ||
                readiness?.isVerified == true ||
                mapReadiness?.isMapUsable == true ||
                hasCachedBundle {
                return nil
            }
        }

        if !NetworkMonitor.shared.isOnline {
            let campaignIdString = campaignId.uuidString
            let downloadState = await CampaignRepository.shared.getDownloadState(campaignId: campaignIdString)
            let hasCachedBundle = await CampaignRepository.shared.getCampaignMapBundle(campaignId: campaignIdString) != nil
            if downloadState?.isAvailableOffline == true || hasCachedBundle {
                return nil
            }
            return "This campaign is not stored on this device yet. Reconnect for a moment so WolfGrid can prepare the area automatically, then try again."
        }

        do {
            let row = try await fetchCampaignSessionGateRow(campaignId: campaignId)
            let status = (row.provisionStatus ?? "").lowercased()
            if status == "failed" {
                return "Campaign provisioning failed. Open the campaign and retry provisioning from details, or contact support."
            }
            if status != "ready" {
                return "Campaign is still provisioning. Wait until it finishes, then try starting a session again."
            }
            return nil
        } catch {
            print("⚠️ [CampaignsAPI] sessionStartBlockReason failed: \(error.localizedDescription)")
            return "Could not verify campaign readiness. Check your connection and try again."
        }
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
struct CampaignProvisionTimings: Codable, Equatable {
    let version: Int?
    let totalMs: Int?
    let stages: [String: Int]?
    let linker: [String: Int]?
    let counts: [String: Int]?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case version
        case totalMs = "total_ms"
        case stages
        case linker
        case counts
        case updatedAt = "updated_at"
    }

    var slowestStageDescription: String? {
        let merged = (stages ?? [:]).merging(linker ?? [:]) { current, _ in current }
        guard let slowest = merged.max(by: { $0.value < $1.value }) else { return nil }
        return "\(slowest.key)=\(slowest.value)ms"
    }
}

    struct CampaignProvisionResponse: Codable {
        var success: Bool?
        var addressesSaved: Int?
        var buildingsSaved: Int?
    /// Canonical road count from `campaign_road_metadata` when backend includes it.
    var roadsCount: Int?
    /// Legacy/alternate field name from some deploys.
        var roadsSaved: Int?
        var message: String?
        var error: String?
        var accepted: Bool?
        var dataConfidenceScore: Double?
        var dataConfidenceLabel: DataConfidenceLabel?
    var dataConfidenceReason: String?
    var dataConfidenceSummary: CampaignDataConfidenceSummary?
    var provisionStatus: CampaignProvisionStatus?
    var provisionPhase: CampaignProvisionPhase?
    var provisionSource: CampaignProvisionSource?
    var mapReady: Bool?
    var optimized: Bool?
    var postprocessDeferred: Bool?
    var parcelEnrichmentStatus: String?
    var provisionTimings: CampaignProvisionTimings?
    var linkerPath: String?
    var warning: String?
    var hasParcels: Bool?
    var buildingLinkConfidence: Double?
    var mapMode: CampaignMapMode?
    var coverageScore: Int?
    var dataQuality: CampaignDataQuality?
    var standardModeRecommended: Bool?
    var dataQualityReason: String?
    var code: String?
    var homeCount: Int?
    var maxCampaignHomes: Int?
    var maxAppHomes: Int?
    var suggestedCampaigns: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case addressesSaved = "addresses_saved"
        case buildingsSaved = "buildings_saved"
        case roadsCount = "roads_count"
            case roadsSaved = "roads_saved"
            case message
            case error
            case accepted
            case dataConfidenceScore = "data_confidence_score"
        case dataConfidenceLabel = "data_confidence_label"
        case dataConfidenceReason = "data_confidence_reason"
        case dataConfidenceSummary = "data_confidence_summary"
        case provisionStatus = "provision_status"
        case provisionPhase = "provision_phase"
        case provisionSource = "provision_source"
        case mapReady = "map_ready"
        case optimized
        case postprocessDeferred = "postprocess_deferred"
        case parcelEnrichmentStatus = "parcel_enrichment_status"
        case provisionTimings = "provision_timings"
        case linkerPath = "linker_path"
        case warning
        case hasParcels = "has_parcels"
        case buildingLinkConfidence = "building_link_confidence"
        case mapMode = "map_mode"
        case coverageScore = "coverage_score"
        case dataQuality = "data_quality"
        case standardModeRecommended = "standard_mode_recommended"
        case dataQualityReason = "reason"
        case code
        case homeCount = "home_count"
        case maxCampaignHomes = "max_campaign_homes"
        case maxAppHomes = "max_app_homes"
        case suggestedCampaigns = "suggested_campaigns"
    }
}


struct CampaignProvisionState: Codable {
    let id: UUID
    let provisionStatus: CampaignProvisionStatus?
    let provisionSource: CampaignProvisionSource?
    let provisionPhase: CampaignProvisionPhase?
    let provisionedAt: Date?
    let addressesReadyAt: Date?
    let mapReadyAt: Date?
    let optimizedAt: Date?
    let snapshotBucket: String?
    let snapshotPrefix: String?
    let snapshotBuildingsURL: String?
    let snapshotRoadsURL: String?
    let addressSource: String?
    let coverageScore: Int?
    let dataQuality: CampaignDataQuality?
    let standardModeRecommended: Bool?
    let dataQualityReason: String?
    let provisionTimings: CampaignProvisionTimings?
    let provisionError: String?
    let provisionMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case provisionStatus = "provision_status"
        case provisionSource = "provision_source"
        case provisionPhase = "provision_phase"
        case provisionedAt = "provisioned_at"
        case addressesReadyAt = "addresses_ready_at"
        case mapReadyAt = "map_ready_at"
        case optimizedAt = "optimized_at"
        case snapshotBucket = "snapshot_bucket"
        case snapshotPrefix = "snapshot_prefix"
        case snapshotBuildingsURL = "snapshot_buildings_url"
        case snapshotRoadsURL = "snapshot_roads_url"
        case addressSource = "address_source"
        case coverageScore = "coverage_score"
        case dataQuality = "data_quality"
        case standardModeRecommended = "standard_mode_recommended"
        case dataQualityReason = "data_quality_reason"
        case provisionTimings = "provision_timings"
        case provisionError = "provision_error"
        case provisionMessage = "provision_message"
    }
}

// MARK: - Campaign Assignments API

struct CampaignAssignmentSummary: Decodable, Identifiable, Equatable {
    let id: UUID
    let campaignId: UUID
    let workspaceId: UUID
    // Whole-team assignments legitimately have no individual assignee.
    let assignedToUserId: UUID?
    let assignedByUserId: UUID?
    let mode: String
    let goalHomes: Int?
    let zoneIndex: Int?
    let status: String
    let dueAt: String?
    let notes: String?
    let campaign: CampaignAssignmentCampaignSummary?
    let assignee: CampaignAssignmentAssigneeSummary?

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case workspaceId = "workspace_id"
        case assignedToUserId = "assigned_to_user_id"
        case assignedByUserId = "assigned_by_user_id"
        case mode
        case goalHomes = "goal_homes"
        case zoneIndex = "zone_index"
        case status
        case dueAt = "due_at"
        case notes
        case campaign
        case assignee
    }

    var isActive: Bool {
        !["completed", "complete", "cancelled", "canceled", "archived", "declined"]
            .contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

struct CampaignAssignmentCampaignSummary: Decodable, Equatable {
    let id: UUID
    let name: String?
    let status: String?
}

struct CampaignAssignmentAssigneeSummary: Decodable, Equatable {
    let id: UUID
    let fullName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
    }

    var displayName: String {
        fullName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? email?.split(separator: "@").first.map(String.init)
            ?? "Team member"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct CampaignAssignmentsResponse: Decodable {
    let assignments: [CampaignAssignmentSummary]
    let role: String
}

@MainActor
final class CampaignAssignmentsAPI {
    static let shared = CampaignAssignmentsAPI()

    private init() {}

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "WOLFGRID_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://wolfgrid.app"
    }

    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "wolfgrid.app" else {
            return baseURL
        }
        return "https://wolfgrid.app"
    }

    func fetchAssignments(workspaceId: UUID) async throws -> CampaignAssignmentsResponse {
        var components = URLComponents(string: "\(requestBaseURL)/api/campaign-assignments")!
        components.queryItems = [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        guard let url = components.url else {
            throw NSError(domain: "CampaignAssignmentsAPI", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid campaign assignments URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = try await SupabaseManager.shared.client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CampaignAssignmentsAPI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No HTTP response for campaign assignments."
            ])
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error) ?? "Campaign assignments failed."
            throw NSError(domain: "CampaignAssignmentsAPI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        return try JSONDecoder().decode(CampaignAssignmentsResponse.self, from: data)
    }

    func respond(assignmentId: UUID, action: String) async throws {
        guard let url = URL(string: "\(requestBaseURL)/api/campaign-assignments/status") else {
            throw NSError(domain: "CampaignAssignmentsAPI", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid campaign assignment response URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = try await SupabaseManager.shared.client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "assignmentId": assignmentId.uuidString,
            "action": action,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CampaignAssignmentsAPI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No HTTP response for campaign assignment."
            ])
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error)
                ?? "Could not update assignment."
            throw NSError(domain: "CampaignAssignmentsAPI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
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
            addresses: [],
            totalFlyers: 0
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
        if !NetworkMonitor.shared.isOnline,
           let cachedCampaign = await CampaignRepository.shared.getCachedCampaign(campaignId: id) {
            print("📴 [API DEBUG] Loaded cached campaign V2 for offline detail: \(id)")
            return cachedCampaign
        }

        // Fetch campaign from DB using the shared API instance
        let dbRow: CampaignDBRow
        do {
            dbRow = try await CampaignsAPI.shared.fetchCampaignDBRow(id: id)
        } catch {
            if let cachedCampaign = await CampaignRepository.shared.getCachedCampaign(campaignId: id) {
                print("⚠️ [API DEBUG] Campaign fetch failed, using cached campaign: \(error.localizedDescription)")
                return cachedCampaign
            }
            throw error
        }
        
        // Fetch addresses using the shared API instance
        async let addressesTask = CampaignsAPI.shared.fetchAddresses(campaignId: id)
        async let addressCountTask = CampaignsAPI.shared.fetchCampaignAddressCount(campaignId: id)
        let addresses = try await addressesTask
        let addressCount = (try? await addressCountTask) ?? addresses.count
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
            type: dbRow.campaignType,
            addressSource: dbRow.addressSource,
            addresses: campaignAddresses,
            totalFlyers: max(campaignAddresses.count, addressCount),
            scans: dbRow.scans,
            conversions: dbRow.conversions,
            createdAt: dbRow.createdAt,
            status: dbRow.status ?? .draft,
            seedQuery: dbRow.region,
            dataConfidence: dbRow.dataConfidence,
            provisionStatus: dbRow.provisionStatus,
            provisionSource: dbRow.provisionSource,
            provisionPhase: dbRow.provisionPhase,
            addressesReadyAt: dbRow.addressesReadyAt,
            mapReadyAt: dbRow.mapReadyAt,
            optimizedAt: dbRow.optimizedAt,
            hasParcels: dbRow.hasParcels,
            buildingLinkConfidence: dbRow.buildingLinkConfidence,
            mapMode: dbRow.mapMode,
            coverageScore: dbRow.coverageScore,
            dataQuality: dbRow.dataQuality,
            standardModeRecommended: dbRow.standardModeRecommended,
            dataQualityReason: dbRow.dataQualityReason
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
            addressesJSON: [],
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
