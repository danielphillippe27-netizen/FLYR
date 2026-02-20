import Foundation
import Supabase
import Combine

/// Service for fetching and caching building data including address, residents, and QR status
@MainActor
class BuildingDataService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var buildingData: BuildingData = .empty
    
    // MARK: - Private Properties
    
    private let supabase: SupabaseClient
    private var cache: [String: CachedBuildingData] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    
    // MARK: - Initialization
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    // MARK: - Public Methods
    
    /// Fetches complete building data for a given GERS ID and campaign
    /// - Parameters:
    ///   - gersId: The Overture Maps GERS ID string of the building (from map feature)
    ///   - campaignId: The campaign ID to fetch data for
    ///   - addressId: Optional campaign address ID from the tapped feature; when set, we try direct lookup first so the card shows linked state
    ///   - preferredAddressId: When multiple addresses exist, which one to show as primary (e.g. selected from list); nil = show first or list
    func fetchBuildingData(gersId: String, campaignId: UUID, addressId: UUID? = nil, preferredAddressId: UUID? = nil) async {
        // Check cache first (include addressId when present so direct lookups are cached)
        let cacheKey = addressId.map { "\(campaignId.uuidString):addr:\($0.uuidString)" } ?? "\(campaignId.uuidString):\(gersId)"
        if let cached = cache[cacheKey], cached.isValid(ttl: cacheTTL) {
            if let preferred = preferredAddressId, !cached.data.addresses.isEmpty,
               let chosen = cached.data.addresses.first(where: { $0.id == preferred }) {
                buildingData = BuildingData(
                    isLoading: false,
                    error: nil,
                    address: chosen,
                    addresses: cached.data.addresses,
                    residents: cached.data.residents,
                    qrStatus: cached.data.qrStatus,
                    buildingExists: cached.data.buildingExists,
                    addressLinked: cached.data.addressLinked,
                    contactName: cached.data.contactName,
                    leadStatus: cached.data.leadStatus,
                    productInterest: cached.data.productInterest,
                    followUpDate: cached.data.followUpDate,
                    aiSummary: cached.data.aiSummary
                )
            } else {
                buildingData = cached.data
            }
            return
        }
        
        // Set loading state
        buildingData = .loading
        
        let decoder = JSONDecoder.supabaseDates
        
        do {
            var resolvedAddress: CampaignAddressResponse?
            var buildingExists = false
            var goldPathAddresses: [CampaignAddressResponse] = []
            
            // Step 0: If we have address_id from the tapped feature, try direct lookup first (so we "have the link")
            if let addrId = addressId {
                let directQuery = supabase
                    .from("campaign_addresses")
                    .select("""
                        id,
                        house_number,
                        street_name,
                        formatted,
                        locality,
                        region,
                        postal_code,
                        gers_id,
                        building_gers_id,
                        scans,
                        last_scanned_at,
                        qr_code_base64,
                        contact_name,
                        lead_status,
                        product_interest,
                        follow_up_date,
                        raw_transcript,
                        ai_summary
                    """)
                    .eq("id", value: addrId.uuidString)
                    .eq("campaign_id", value: campaignId.uuidString)
                let directResponse = try await directQuery.execute()
                let directAddresses = try decoder.decode([CampaignAddressResponse].self, from: directResponse.data)
                if let addr = directAddresses.first {
                    resolvedAddress = addr
                    buildingExists = true
                }
            }
            
            // Step 1: If no direct match, try lookup by GERS ID (string) in campaign_addresses
            // Try both original and lowercased GERS ID to handle case differences
            if resolvedAddress == nil {
                let gersIdLower = gersId.lowercased()
                let orFilter = gersIdLower == gersId
                    ? "gers_id.eq.\(gersId),building_gers_id.eq.\(gersId)"
                    : "gers_id.eq.\(gersId),building_gers_id.eq.\(gersId),gers_id.eq.\(gersIdLower),building_gers_id.eq.\(gersIdLower)"
                let addressQuery = supabase
                    .from("campaign_addresses")
                    .select("""
                        id,
                        house_number,
                        street_name,
                        formatted,
                        locality,
                        region,
                        postal_code,
                        gers_id,
                        building_gers_id,
                        scans,
                        last_scanned_at,
                        qr_code_base64,
                        contact_name,
                        lead_status,
                        product_interest,
                        follow_up_date,
                        raw_transcript,
                        ai_summary
                    """)
                    .eq("campaign_id", value: campaignId.uuidString)
                    .or(orFilter)
                
                let addressResponse = try await addressQuery.execute()
                let addresses = try decoder.decode([CampaignAddressResponse].self, from: addressResponse.data)
                resolvedAddress = addresses.first
                buildingExists = resolvedAddress != nil
            }
            
            // Step 1b: Gold path — campaign_addresses.building_id = gers_id (ref_buildings_gold.id)
            if resolvedAddress == nil, UUID(uuidString: gersId) != nil {
                let goldQuery = supabase
                    .from("campaign_addresses")
                    .select("""
                        id,
                        house_number,
                        street_name,
                        formatted,
                        locality,
                        region,
                        postal_code,
                        gers_id,
                        building_gers_id,
                        scans,
                        last_scanned_at,
                        qr_code_base64,
                        contact_name,
                        lead_status,
                        product_interest,
                        follow_up_date,
                        raw_transcript,
                        ai_summary
                    """)
                    .eq("campaign_id", value: campaignId.uuidString)
                    .eq("building_id", value: gersId)
                let goldResponse = try await goldQuery.execute()
                let decoded = try decoder.decode([CampaignAddressResponse].self, from: goldResponse.data)
                goldPathAddresses = decoded
                if let first = decoded.first {
                    resolvedAddress = first
                    buildingExists = true
                }
            }
            
            // Step 2: If still no match, get all addresses linked to this building from Supabase.
            // building_address_links.building_id is buildings.id (UUID), so resolve building first by gers_id or id.
            var supabaseLinkAddresses: [CampaignAddressResponse] = []
            if let buildingUuid = try? await resolveBuildingUuid(gersId: gersId) {
                let linkQuery = supabase
                    .from("building_address_links")
                    .select("""
                        address_id,
                        campaign_addresses!inner (
                            id,
                            house_number,
                            street_name,
                            formatted,
                            locality,
                            region,
                            postal_code,
                            gers_id,
                            building_gers_id,
                            scans,
                            last_scanned_at,
                            qr_code_base64,
                            contact_name,
                            lead_status,
                            product_interest,
                            follow_up_date,
                            raw_transcript,
                            ai_summary
                        )
                    """)
                    .eq("campaign_id", value: campaignId.uuidString)
                    .eq("building_id", value: buildingUuid.uuidString)
                let linkResponse = try await linkQuery.execute()
                let links = try decoder.decode([BuildingAddressLinkResponse].self, from: linkResponse.data)
                supabaseLinkAddresses = links.compactMap(\.campaignAddress)
                if resolvedAddress == nil, let first = supabaseLinkAddresses.first {
                    resolvedAddress = first
                    buildingExists = true
                }
            }
            
            // Step 3: Fetch all addresses for this building (multiple units): API first, then Supabase fallback
            var allAddressResponses: [CampaignAddressResponse] = []
            if let apiAddresses = try? await BuildingLinkService.shared.fetchAddressesForBuilding(campaignId: campaignId.uuidString, buildingId: gersId) {
                allAddressResponses = apiAddresses
            }
            if allAddressResponses.isEmpty, !supabaseLinkAddresses.isEmpty {
                allAddressResponses = supabaseLinkAddresses
            }
            if allAddressResponses.isEmpty, !goldPathAddresses.isEmpty {
                allAddressResponses = goldPathAddresses
            }
            if allAddressResponses.isEmpty, let single = resolvedAddress {
                allAddressResponses = [single]
            }
            let resolvedAddresses = allAddressResponses.map { $0.toResolvedAddress(fallbackGersId: gersId) }
            let preferred = preferredAddressId ?? addressId
            let primaryAddress = preferred.flatMap { id in resolvedAddresses.first(where: { $0.id == id }) }
                ?? resolvedAddresses.first
            
            // Step 4: Process primary address (contacts, QR, etc.)
            let displayAddress = primaryAddress ?? resolvedAddresses.first
            if let address = displayAddress {
                let responseForPrimary = allAddressResponses.first(where: { $0.id == address.id }) ?? resolvedAddress
                let qrStatus = responseForPrimary?.toQRStatus() ?? .empty
                let residents = try await fetchContactsForAddress(addressId: address.id)
                let data = BuildingData(
                    isLoading: false,
                    error: nil,
                    address: address,
                    addresses: resolvedAddresses,
                    residents: residents,
                    qrStatus: qrStatus,
                    buildingExists: buildingExists || !resolvedAddresses.isEmpty,
                    addressLinked: true,
                    contactName: responseForPrimary?.contactName ?? resolvedAddress?.contactName,
                    leadStatus: responseForPrimary?.leadStatus ?? resolvedAddress?.leadStatus,
                    productInterest: responseForPrimary?.productInterest ?? resolvedAddress?.productInterest,
                    followUpDate: responseForPrimary?.followUpDate ?? resolvedAddress?.followUpDate,
                    aiSummary: responseForPrimary?.aiSummary ?? resolvedAddress?.aiSummary
                )
                buildingData = data
                cache[cacheKey] = CachedBuildingData(data: data, timestamp: Date())
            } else {
                // No address found
                let data = BuildingData(
                    isLoading: false,
                    error: nil,
                    address: nil,
                    addresses: [],
                    residents: [],
                    qrStatus: .empty,
                    buildingExists: buildingExists,
                    addressLinked: false,
                    contactName: nil,
                    leadStatus: nil,
                    productInterest: nil,
                    followUpDate: nil,
                    aiSummary: nil
                )
                buildingData = data
                cache[cacheKey] = CachedBuildingData(data: data, timestamp: Date())
            }
        } catch {
            buildingData = BuildingData(
                isLoading: false,
                error: error,
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
    
    /// Resolves map building identifier to buildings.id (UUID). Tries id and gers_id with both original and lowercased variants.
    private func resolveBuildingUuid(gersId: String) async throws -> UUID? {
        let trimmed = gersId.trimmingCharacters(in: .whitespaces)
        // Try both original case and lowercased (Overture GERS IDs are UUIDs but may have different casing)
        let lower = trimmed.lowercased()
        let candidates = Set([trimmed, lower])
        // Only query if at least one candidate looks like a UUID
        guard candidates.contains(where: { UUID(uuidString: $0) != nil }) else { return nil }
        let orParts = candidates.flatMap { c in ["id.eq.\(c)", "gers_id.eq.\(c)"] }
        let response = try await supabase
            .from("buildings")
            .select("id")
            .or(orParts.joined(separator: ","))
            .limit(1)
            .execute()
        struct Row: Decodable { let id: UUID }
        let rows = try JSONDecoder().decode([Row].self, from: response.data)
        return rows.first?.id
    }
    
    /// Fetches contacts for a given address ID
    /// - Parameter addressId: The address ID to fetch contacts for
    /// - Returns: Array of contacts
    private func fetchContactsForAddress(addressId: UUID) async throws -> [Contact] {
        let contactsQuery = supabase
            .from("contacts")
            .select("*")
            .eq("address_id", value: addressId.uuidString)
            .order("created_at", ascending: false)
        
        let contactsResponse = try await contactsQuery.execute()
        let decoder = JSONDecoder.supabaseDates
        return try decoder.decode([Contact].self, from: contactsResponse.data)
    }
    
    /// Clears the cache
    func clearCache() {
        cache.removeAll()
    }
    
    /// Clears a specific cache entry
    /// - Parameters:
    ///   - gersId: The GERS ID string
    ///   - campaignId: The campaign ID
    func clearCacheEntry(gersId: String, campaignId: UUID) {
        let cacheKey = "\(campaignId.uuidString):\(gersId)"
        cache.removeValue(forKey: cacheKey)
    }
    
    /// Clears the cache entry for a specific address (used when address-linked data changes, e.g. new resident)
    func clearCacheEntry(addressId: UUID, campaignId: UUID) {
        let cacheKey = "\(campaignId.uuidString):addr:\(addressId.uuidString)"
        cache.removeValue(forKey: cacheKey)
    }
    
    /// Invalidates cache entries older than TTL
    func pruneCache() {
        let now = Date()
        cache = cache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < cacheTTL
        }
    }
}

// MARK: - Convenience Initializer

extension BuildingDataService {
    /// Creates a BuildingDataService using the shared Supabase manager
    static var shared: BuildingDataService {
        BuildingDataService(supabase: SupabaseManager.shared.client)
    }
}

// MARK: - Error Types

enum BuildingDataError: LocalizedError {
    case buildingNotFound
    case noAddressLinked
    case networkError(Error)
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .buildingNotFound:
            return "Building not found"
        case .noAddressLinked:
            return "No address data linked to this building"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}
