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
    func fetchBuildingData(gersId: String, campaignId: UUID, addressId: UUID? = nil) async {
        // Check cache first (include addressId when present so direct lookups are cached)
        let cacheKey = addressId.map { "\(campaignId.uuidString):addr:\($0.uuidString)" } ?? "\(campaignId.uuidString):\(gersId)"
        if let cached = cache[cacheKey], cached.isValid(ttl: cacheTTL) {
            buildingData = cached.data
            return
        }
        
        // Set loading state
        buildingData = .loading
        
        let decoder = JSONDecoder.supabaseDates
        
        do {
            var resolvedAddress: CampaignAddressResponse?
            var buildingExists = false
            
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
            if resolvedAddress == nil {
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
                    .or("gers_id.eq.\(gersId),building_gers_id.eq.\(gersId)")
                
                let addressResponse = try await addressQuery.execute()
                let addresses = try decoder.decode([CampaignAddressResponse].self, from: addressResponse.data)
                resolvedAddress = addresses.first
                buildingExists = resolvedAddress != nil
            }
            
            // Step 2: If still no match, query building_address_links by GERS ID string (building_id is Overture GERS ID, not buildings.id)
            if resolvedAddress == nil {
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
                    .eq("building_id", value: gersId)
                
                let linkResponse = try await linkQuery.execute()
                let links = try decoder.decode([BuildingAddressLinkResponse].self, from: linkResponse.data)
                if let first = links.first {
                    resolvedAddress = first.campaignAddress
                    buildingExists = true
                }
            }
            
            // Step 3: Process resolved address
            if let address = resolvedAddress {
                let resolved = address.toResolvedAddress(fallbackGersId: gersId)
                let qrStatus = address.toQRStatus()
                
                // Step 4: Fetch contacts linked to this address
                let residents = try await fetchContactsForAddress(addressId: resolved.id)
                
                let data = BuildingData(
                    isLoading: false,
                    error: nil,
                    address: resolved,
                    residents: residents,
                    qrStatus: qrStatus,
                    buildingExists: buildingExists,
                    addressLinked: true,
                    contactName: address.contactName,
                    leadStatus: address.leadStatus,
                    productInterest: address.productInterest,
                    followUpDate: address.followUpDate,
                    aiSummary: address.aiSummary
                )
                
                buildingData = data
                cache[cacheKey] = CachedBuildingData(data: data, timestamp: Date())
            } else {
                // No address found
                let data = BuildingData(
                    isLoading: false,
                    error: nil,
                    address: nil,
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
