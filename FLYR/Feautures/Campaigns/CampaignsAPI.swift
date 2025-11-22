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

final class CampaignsAPI {
    static let shared = CampaignsAPI()
    private let client = SupabaseManager.shared.client

    // All campaigns
    func fetchCampaigns() async throws -> [Campaign] {
        let res: PostgrestResponse<[Campaign]> = try await client
            .from("campaigns")
            .select()
            .order("created_at", ascending: false)
            .execute()
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
        print("🌐 [API DEBUG] Campaign type: \(payload.type.rawValue)")
        print("🌐 [API DEBUG] Address source: \(payload.addressSource.rawValue)")
        print("🌐 [API DEBUG] Target count: \(payload.addressTargetCount)")
        print("🌐 [API DEBUG] Seed query: \(payload.seedQuery ?? "nil")")
        print("🌐 [API DEBUG] Seed coordinates: (\(payload.seedLat ?? 0), \(payload.seedLon ?? 0))")
        print("🌐 [API DEBUG] Addresses JSON count: \(payload.addressesJSON.count)")

        let shim = SupabaseClientShim()
        
        // 1. Get current user ID
        let userId = try await shim.currentUserId()
        print("🌐 [API DEBUG] User ID: \(userId)")
        
        // 2. Insert campaign row into campaigns table
        let campaignValues: [String: Any] = [
            "owner_id": userId.uuidString,
            "title": payload.name,
            "description": payload.description,
            // total_flyers removed - computed automatically from addresses
            "scans": 0,
            "conversions": 0,
            "region": payload.seedQuery as Any
        ]
        
        print("🌐 [API DEBUG] Inserting campaign into DB...")
        let dbRow: CampaignDBRow = try await shim.insertReturning("campaigns", values: campaignValues)
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
            type: payload.type,
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
    func fetchCampaignsMetadata() async throws -> [CampaignDBRow] {
        print("🌐 [API DEBUG] Fetching campaigns metadata (no addresses)")
        
        let res: PostgrestResponse<[CampaignDBRow]> = try await client
            .from("campaigns")
            .select()
            .order("created_at", ascending: false)
            .execute()
        
        print("✅ [API DEBUG] Fetched \(res.value.count) campaigns metadata")
        return res.value
    }
    
    // Fetch Campaigns V2 - REAL SUPABASE INTEGRATION
    // Now only fetches campaign metadata, NOT addresses (for performance)
    func fetchCampaignsV2() async throws -> [CampaignV2] {
        print("🌐 [API DEBUG] Fetching campaigns V2 from Supabase (metadata only, no addresses)")
        
        // 1. Fetch campaigns from DB
        let res: PostgrestResponse<[CampaignDBRow]> = try await client
            .from("campaigns")
            .select()
            .order("created_at", ascending: false)
            .execute()
        
        let dbRows = res.value
        print("✅ [API DEBUG] Fetched \(dbRows.count) campaigns from DB")
        
        // 2. Convert each campaign to CampaignV2 WITHOUT fetching addresses
        // Addresses will be fetched lazily when campaign detail is opened
        var campaigns: [CampaignV2] = []
        for dbRow in dbRows {
            // Create CampaignV2 with empty addresses array
            // Addresses and count will be loaded when user opens the campaign detail view
            // For now, set totalFlyers to 0 - it will be updated when addresses are loaded
            let campaign = CampaignV2(
                id: dbRow.id,
                name: dbRow.title,
                type: .flyer, // Default - should be stored in DB
                addressSource: .closestHome, // Default - should be stored in DB
                addresses: [], // Empty - will be loaded on demand
                totalFlyers: 0, // Will be set when addresses are loaded
                scans: dbRow.scans,
                conversions: dbRow.conversions,
                createdAt: dbRow.createdAt,
                status: .draft,
                seedQuery: dbRow.region
            )
            campaigns.append(campaign)
        }
        
        print("✅ [API DEBUG] Converted \(campaigns.count) campaigns to CampaignV2 (addresses will load on demand)")
        return campaigns
    }
    
    // MARK: - Bulk Address Operations
    
    /// Bulk add addresses to a campaign using Supabase RPC
    func bulkAddAddresses(campaignID: UUID, records: [[String: Any]]) async throws -> Int {
        // Convert to JSON-encodable
        let payload = try JSONSerialization.data(withJSONObject: records)
        let jsonb = String(data: payload, encoding: .utf8)!

        struct RPCResult: Decodable { let add_addresses_to_campaign: Int }
        let res: PostgrestResponse<RPCResult> = try await client
            .rpc("add_addresses_to_campaign",
                 params: ["p_campaign_id": campaignID.uuidString,
                          "p_addresses": jsonb])
            .execute()
        return res.value.add_addresses_to_campaign
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
}

// MARK: - Campaign V2 API

/// Protocol for CampaignV2 API operations
protocol CampaignsV2APIType {
    func fetchCampaigns() async throws -> [CampaignV2]
    func fetchCampaign(id: UUID) async throws -> CampaignV2
    func createCampaign(_ draft: CampaignV2Draft) async throws -> CampaignV2
}

/// Mock implementation for CampaignV2 API
final class CampaignsV2APIMock: CampaignsV2APIType {
    private var mockCampaigns: [CampaignV2] = []
    
    func fetchCampaigns() async throws -> [CampaignV2] {
        // Simulate network latency
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        return mockCampaigns
    }
    
    func fetchCampaign(id: UUID) async throws -> CampaignV2 {
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        guard let campaign = mockCampaigns.first(where: { $0.id == id }) else {
            throw NSError(domain: "CampaignV2API", code: 404, userInfo: [NSLocalizedDescriptionKey: "Campaign not found"])
        }
        return campaign
    }
    
    func createCampaign(_ draft: CampaignV2Draft) async throws -> CampaignV2 {
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
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
    
    func fetchCampaigns() async throws -> [CampaignV2] {
        return try await api.fetchCampaignsV2()
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
        
        // Convert to CampaignV2
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
            status: .draft,
            seedQuery: dbRow.region
        )
    }
    
    func createCampaign(_ draft: CampaignV2Draft) async throws -> CampaignV2 {
        // Use the real createV2 method
        let payload = CampaignCreatePayloadV2(
            name: draft.name,
            description: "",
            type: draft.type,
            addressSource: draft.addressSource,
            addressTargetCount: draft.addresses.count,
            seedQuery: nil,
            seedLon: nil,
            seedLat: nil,
            addressesJSON: draft.addresses
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
