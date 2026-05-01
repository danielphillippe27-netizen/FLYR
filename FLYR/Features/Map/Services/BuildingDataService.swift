import Foundation
import Supabase
import Combine
import CoreLocation
import MapboxMaps

/// Service for fetching and caching building data including address, residents, and QR status
@MainActor
class BuildingDataService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var buildingData: BuildingData = .empty
    
    // MARK: - Private Properties
    
    private let supabase: SupabaseClient
    private var cache: [String: CachedBuildingData] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    private var fetchGeneration = 0

    private struct AddressFeatureCandidate {
        let feature: AddressFeature
        let score: Int
        let distanceMeters: Double
    }
    
    // MARK: - Initialization
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    static func sortAddressesForDisplay(_ addresses: [CampaignAddressResponse]) -> [CampaignAddressResponse] {
        addresses.sorted { lhs, rhs in
            let lhsStreet = normalizedStreetName(for: lhs)
            let rhsStreet = normalizedStreetName(for: rhs)
            if lhsStreet != rhsStreet {
                return lhsStreet.localizedStandardCompare(rhsStreet) == .orderedAscending
            }

            let lhsHouse = houseNumberSortParts(for: lhs)
            let rhsHouse = houseNumberSortParts(for: rhs)
            switch (lhsHouse.number, rhsHouse.number) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                break
            }

            if lhsHouse.suffix != rhsHouse.suffix {
                return lhsHouse.suffix.localizedStandardCompare(rhsHouse.suffix) == .orderedAscending
            }

            if lhsHouse.raw != rhsHouse.raw {
                return lhsHouse.raw.localizedStandardCompare(rhsHouse.raw) == .orderedAscending
            }

            let lhsFormatted = (lhs.formatted ?? "\(lhs.houseNumber ?? "") \(lhs.streetName ?? "")")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsFormatted = (rhs.formatted ?? "\(rhs.houseNumber ?? "") \(rhs.streetName ?? "")")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return lhsFormatted.localizedStandardCompare(rhsFormatted) == .orderedAscending
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetches complete building data for a given GERS ID and campaign
    /// - Parameters:
    ///   - gersId: The Overture Maps GERS ID string of the building (from map feature)
    ///   - campaignId: The campaign ID to fetch data for
    ///   - addressId: Optional campaign address ID from the tapped feature; when set, we try direct lookup first so the card shows linked state
    ///   - preferredAddressId: When multiple addresses exist, which one to show as primary (e.g. selected from list); nil = show first or list
    ///   - addressTextHint: Address text from the tapped map feature. Used only to disambiguate bad multi-link results.
    func fetchBuildingData(gersId: String, campaignId: UUID, addressId: UUID? = nil, preferredAddressId: UUID? = nil, addressTextHint: String? = nil) async {
        fetchGeneration += 1
        let requestGeneration = fetchGeneration

        // Check cache first (include addressId when present so direct lookups are cached)
        let cacheKey = addressId.map { "\(campaignId.uuidString):addr:\($0.uuidString)" } ?? "\(campaignId.uuidString):\(gersId)"
        if let cached = cache[cacheKey], cached.isValid(ttl: cacheTTL) {
            guard requestGeneration == fetchGeneration else { return }
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

        let localData = await loadLocalBuildingData(
            gersId: gersId,
            campaignId: campaignId,
            addressId: addressId,
            preferredAddressId: preferredAddressId
        )
        guard requestGeneration == fetchGeneration else { return }
        if let localData {
            buildingData = localData
            cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())
        } else {
            buildingData = .loading
        }

        if !NetworkMonitor.shared.isOnline {
            guard requestGeneration == fetchGeneration else { return }
            if let localData {
                buildingData = localData
                cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())
            } else {
                buildingData = BuildingData(
                    isLoading: false,
                    error: BuildingDataError.noAddressLinked,
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
            return
        }
        
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
            let buildingIdCandidates = (try? await resolveBuildingLinkCandidates(gersId: gersId)) ?? []
            if !buildingIdCandidates.isEmpty {
                let linkQuery = supabase
                    .from("building_address_links")
                    .select("""
                        address_id,
                        match_type,
                        confidence,
                        distance_meters,
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
                    .in("building_id", values: buildingIdCandidates)
                let linkResponse = try await linkQuery.execute()
                let links = try decoder.decode([BuildingAddressLinkResponse].self, from: linkResponse.data)
                supabaseLinkAddresses = Self.chooseAddressLinksForDisplay(links).compactMap(\.campaignAddress)
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
            if let localResolution = await resolveLocalAddressResolution(
                gersId: gersId,
                campaignId: campaignId,
                addressId: addressId
            ),
               !allAddressResponses.isEmpty,
               !localResolution.matchedAddressIDs.isEmpty {
                let requestedIds = Set([addressId, preferredAddressId].compactMap { $0 })
                if !requestedIds.isEmpty {
                    let requestedOnly = allAddressResponses.filter { requestedIds.contains($0.id) }
                    if !requestedOnly.isEmpty {
                        allAddressResponses = requestedOnly
                    }
                } else {
                    let filtered = allAddressResponses.filter { response in
                        localResolution.matchedAddressIDs.contains(response.id)
                    }
                    if !filtered.isEmpty, filtered.count < allAddressResponses.count {
                        allAddressResponses = filtered
                    }
                }
            }
            allAddressResponses = Self.deduplicatedAddressesForDisplay(
                allAddressResponses,
                preferredAddressId: preferredAddressId,
                requestedAddressId: addressId
            )
            allAddressResponses = Self.addressesMatchingHintIfUnambiguous(
                allAddressResponses,
                addressTextHint: addressTextHint,
                preferredAddressId: preferredAddressId,
                requestedAddressId: addressId
            )
            allAddressResponses = Self.sortAddressesForDisplay(allAddressResponses)
            if allAddressResponses.isEmpty,
               let localData = await loadLocalBuildingData(
                    gersId: gersId,
                    campaignId: campaignId,
                    addressId: addressId,
                    preferredAddressId: preferredAddressId
               ) {
                guard requestGeneration == fetchGeneration else { return }
                buildingData = localData
                cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())
                return
            }
            guard requestGeneration == fetchGeneration else { return }
            await CampaignRepository.shared.upsertAddressCaptureMetadata(
                campaignId: campaignId,
                responses: allAddressResponses,
                dirty: false
            )
            guard requestGeneration == fetchGeneration else { return }
            let resolvedAddresses = allAddressResponses.map { $0.toResolvedAddress(fallbackGersId: gersId) }
            let preferred = preferredAddressId ?? addressId
            let primaryAddress = preferred.flatMap { id in resolvedAddresses.first(where: { $0.id == id }) }
                ?? resolvedAddresses.first
            
            // Step 4: Process primary address (contacts, QR, etc.)
            let displayAddress = primaryAddress ?? resolvedAddresses.first
            if let address = displayAddress {
                let responseForPrimary = allAddressResponses.first(where: { $0.id == address.id }) ?? resolvedAddress
                let qrStatus = responseForPrimary?.toQRStatus() ?? localData?.qrStatus ?? .empty
                let residents = try await fetchContactsForAddress(addressId: address.id)
                guard requestGeneration == fetchGeneration else { return }
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
            if let localData = await loadLocalBuildingData(
                gersId: gersId,
                campaignId: campaignId,
                addressId: addressId,
                preferredAddressId: preferredAddressId
            ) {
                guard requestGeneration == fetchGeneration else { return }
                buildingData = localData
                cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())
            } else {
                guard requestGeneration == fetchGeneration else { return }
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
    }

    private static func chooseAddressLinksForDisplay(_ links: [BuildingAddressLinkResponse]) -> [BuildingAddressLinkResponse] {
        guard links.count > 1 else { return links }

        let strongLinks = links.filter { link in
            let matchType = (link.matchType ?? "").lowercased()
            if matchType == "manual" { return true }
            if matchType == "containment_verified" { return true }
            if matchType == "point_on_surface" { return true }
            if matchType == "parcel_verified" { return true }
            return (link.confidence ?? 0) >= 0.9 && matchType != "proximity_fallback"
        }

        if !strongLinks.isEmpty, strongLinks.count < links.count {
            return strongLinks
        }

        return links
    }

    static func deduplicatedAddressesForDisplay(
        _ addresses: [CampaignAddressResponse],
        preferredAddressId: UUID? = nil,
        requestedAddressId: UUID? = nil
    ) -> [CampaignAddressResponse] {
        guard addresses.count > 1 else { return addresses }

        let priorityIds = Set([preferredAddressId, requestedAddressId].compactMap { $0 })
        var orderedKeys: [String] = []
        var keyedAddresses: [String: CampaignAddressResponse] = [:]

        for address in addresses {
            let key = normalizedAddressIdentity(for: address)
            if keyedAddresses[key] == nil {
                orderedKeys.append(key)
                keyedAddresses[key] = address
                continue
            }

            if priorityIds.contains(address.id) {
                keyedAddresses[key] = address
            }
        }

        return orderedKeys.compactMap { keyedAddresses[$0] }
    }

    private static func addressesMatchingHintIfUnambiguous(
        _ addresses: [CampaignAddressResponse],
        addressTextHint: String?,
        preferredAddressId: UUID?,
        requestedAddressId: UUID?
    ) -> [CampaignAddressResponse] {
        guard addresses.count > 1,
              preferredAddressId == nil,
              requestedAddressId == nil,
              let hintIdentity = normalizedAddressIdentity(fromText: addressTextHint),
              !hintIdentity.isEmpty else {
            return addresses
        }

        let exactMatches = addresses.filter { normalizedAddressIdentity(for: $0) == hintIdentity }
        return exactMatches.count == 1 ? exactMatches : addresses
    }
    
    /// Resolves a tapped building identifier into possible link keys.
    /// Some environments store building_address_links.building_id as buildings.id (UUID row id),
    /// while others behave like the public building/GERS id. Query both so Silver campaigns remain readable.
    private func resolveBuildingLinkCandidates(gersId: String) async throws -> [String] {
        let trimmed = gersId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // Try both original case and lowercased (Overture GERS IDs are UUIDs but may have different casing)
        let lower = trimmed.lowercased()
        var candidates = Set([trimmed, lower])

        // Only query the buildings table if at least one candidate looks like a UUID.
        guard candidates.contains(where: { UUID(uuidString: $0) != nil }) else {
            return Array(candidates)
        }

        let orParts = candidates.flatMap { c in ["id.eq.\(c)", "gers_id.eq.\(c)"] }
        let response = try await supabase
            .from("buildings")
            .select("id, gers_id")
            .or(orParts.joined(separator: ","))
            .limit(1)
            .execute()

        struct Row: Decodable {
            let id: UUID
            let gersId: String?

            enum CodingKeys: String, CodingKey {
                case id
                case gersId = "gers_id"
            }
        }

        let rows = try JSONDecoder().decode([Row].self, from: response.data)
        if let row = rows.first {
            candidates.insert(row.id.uuidString)
            candidates.insert(row.id.uuidString.lowercased())
            if let resolvedGersId = row.gersId?.trimmingCharacters(in: .whitespacesAndNewlines), !resolvedGersId.isEmpty {
                candidates.insert(resolvedGersId)
                candidates.insert(resolvedGersId.lowercased())
            }
        }

        return Array(candidates)
    }
    
    /// Fetches contacts for a given address ID
    /// - Parameter addressId: The address ID to fetch contacts for
    /// - Returns: Array of contacts
    private func fetchContactsForAddress(addressId: UUID) async throws -> [Contact] {
        let cached = await ContactRepository.shared.fetchContactsForAddress(addressId: addressId)
        guard NetworkMonitor.shared.isOnline else {
            return cached
        }

        do {
            let contactsQuery = supabase
                .from("contacts")
                .select("*")
                .eq("address_id", value: addressId.uuidString)
                .order("created_at", ascending: false)

            let contactsResponse = try await contactsQuery.execute()
            let decoder = JSONDecoder.supabaseDates
            let remote = try decoder.decode([Contact].self, from: contactsResponse.data)
            await ContactRepository.shared.upsertContacts(remote, userId: nil, workspaceId: nil, dirty: false, syncedAt: Date())
            return remote
        } catch {
            if !cached.isEmpty {
                return cached
            }
            throw error
        }
    }

    private static func normalizedStreetName(for address: CampaignAddressResponse) -> String {
        let explicitStreet = (address.streetName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitStreet.isEmpty {
            return explicitStreet
        }

        let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        return streetOnly.replacingOccurrences(
            of: #"^\s*\d+[A-Za-z\-]*\s+"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedAddressIdentity(for address: CampaignAddressResponse) -> String {
        let house = normalizedHouseNumberIdentity(for: address)
        let street = normalizedStreetName(for: address)
        let primary = [house, normalizedAddressPart(street)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !primary.isEmpty {
            return primary
        }

        let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        let fallback = normalizedAddressPart(streetOnly)
        return fallback.isEmpty ? address.id.uuidString.lowercased() : fallback
    }

    private static func normalizedAddressIdentity(fromText value: String?) -> String? {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let streetOnly = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? raw
        let parts = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return normalizedAddressPart(streetOnly) }

        let house = normalizedAddressPart(String(first))
        let street = parts.count > 1 ? normalizedAddressPart(String(parts[1])) : ""
        let identity = [house, street].filter { !$0.isEmpty }.joined(separator: " ")
        return identity.isEmpty ? nil : identity
    }

    private static func normalizedHouseNumberIdentity(for address: CampaignAddressResponse) -> String {
        let explicitHouse = (address.houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitHouse.isEmpty {
            return normalizedAddressPart(explicitHouse)
        }

        let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        let house = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return normalizedAddressPart(house)
    }

    private static func normalizedAddressPart(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func houseNumberSortParts(for address: CampaignAddressResponse) -> (number: Int?, suffix: String, raw: String) {
        let rawHouseNumber = (address.houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue: String
        if !rawHouseNumber.isEmpty {
            rawValue = rawHouseNumber
        } else {
            let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
            rawValue = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        }

        let normalized = rawValue.uppercased()
        guard let range = normalized.range(of: #"^\d+"#, options: .regularExpression) else {
            return (nil, normalized, normalized)
        }

        let number = Int(normalized[range])
        let suffix = normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (number, suffix, normalized)
    }

    private struct LocalAddressResolution {
        let buildingFeature: BuildingFeature?
        let resolvedAddresses: [ResolvedAddress]
        let matchedAddressIDs: Set<UUID>
    }

    private func resolveLocalAddressResolution(
        gersId: String,
        campaignId: UUID,
        addressId: UUID?
    ) async -> LocalAddressResolution? {
        guard let bundle = await CampaignRepository.shared.getCampaignMapBundle(campaignId: campaignId.uuidString) else {
            return nil
        }

        let normalizedGersId = gersId.lowercased()
        let buildingFeature = bundle.buildings.features.first { feature in
            if feature.id?.lowercased() == normalizedGersId {
                return true
            }
            return feature.properties.buildingIdentifierCandidates.contains(where: { $0.lowercased() == normalizedGersId })
        }

        var buildingCandidates = Set([normalizedGersId])
        if let buildingFeature {
            buildingCandidates.formUnion(buildingFeature.properties.buildingIdentifierCandidates.map { $0.lowercased() })
        }

        var explicitAddressIds = Set<String>()
        for candidate in buildingCandidates {
            explicitAddressIds.formUnion(bundle.silverBuildingLinks[candidate]?.map { $0.lowercased() } ?? [])
        }
        if let directAddressId = buildingFeature?.properties.addressId?.lowercased() {
            explicitAddressIds.insert(directAddressId)
        }
        if let requestedAddressId = addressId?.uuidString.lowercased() {
            explicitAddressIds.insert(requestedAddressId)
        }

        let explicitMatches = bundle.addresses.features.filter { feature in
            let featureAddressId = (feature.properties.id ?? feature.id)?.lowercased()
            if let featureAddressId, explicitAddressIds.contains(featureAddressId) {
                return true
            }
            if let buildingGersId = feature.properties.buildingGersId?.lowercased(), buildingCandidates.contains(buildingGersId) {
                return true
            }
            return false
        }

        let matchedFeatures: [AddressFeature]
        if let buildingFeature {
            let spatialMatches = inferSpatialAddressFeatures(
                for: buildingFeature,
                in: bundle.addresses.features
            )
            // Containment is the strongest local signal. Link metadata can be stale
            // after relinking, but the screenshots show the address points sitting
            // inside their own footprints, so prefer geometry whenever available.
            matchedFeatures = spatialMatches.isEmpty ? explicitMatches : spatialMatches
        } else if !explicitMatches.isEmpty {
            matchedFeatures = explicitMatches
        } else {
            matchedFeatures = []
        }

        var seen = Set<UUID>()
        var resolvedAddresses: [ResolvedAddress] = []
        for feature in matchedFeatures {
            guard let resolved = resolvedAddress(from: feature, fallbackGersId: gersId),
                  seen.insert(resolved.id).inserted else {
                continue
            }
            resolvedAddresses.append(resolved)
        }
        resolvedAddresses.sort { lhs, rhs in
            lhs.displayStreet.localizedStandardCompare(rhs.displayStreet) == .orderedAscending
        }

        return LocalAddressResolution(
            buildingFeature: buildingFeature,
            resolvedAddresses: resolvedAddresses,
            matchedAddressIDs: Set(resolvedAddresses.map { $0.id })
        )
    }

    private func inferSpatialAddressFeatures(
        for buildingFeature: BuildingFeature,
        in addressFeatures: [AddressFeature]
    ) -> [AddressFeature] {
        let polygons = polygons(from: buildingFeature.geometry)
        guard !polygons.isEmpty else { return [] }

        let insideCandidates = addressFeatures.compactMap { feature -> AddressFeatureCandidate? in
            guard let point = coordinate(from: feature.geometry) else { return nil }
            let inside = polygons.contains { BuildingGeometryHelpers.pointInPolygon(point, polygon: $0) }
            guard inside else { return nil }

            let centroidDistance = polygons.compactMap {
                BuildingGeometryHelpers.distanceToPolygonCentroid(point, polygon: $0)
            }.min() ?? .greatestFiniteMagnitude

            return AddressFeatureCandidate(feature: feature, score: 1000 - Int(min(centroidDistance.rounded(), 300)), distanceMeters: centroidDistance)
        }

        if !insideCandidates.isEmpty {
            return sortedAddressCandidates(insideCandidates)
        }

        let buildingStreet = normalizedStreetHint(for: buildingFeature.properties)
        let buildingHouse = normalizedHouseHint(for: buildingFeature.properties)
        let polygonRadius = max(polygons.compactMap(approximatePolygonRadiusMeters).max() ?? 0, 10)

        let fallbackCandidates = addressFeatures.compactMap { feature -> AddressFeatureCandidate? in
            guard let point = coordinate(from: feature.geometry) else { return nil }
            let centroidDistance = polygons.compactMap {
                BuildingGeometryHelpers.distanceToPolygonCentroid(point, polygon: $0)
            }.min() ?? .greatestFiniteMagnitude

            let featureStreet = normalizedStreetHint(for: feature.properties)
            let featureHouse = normalizedHouseHint(for: feature.properties)
            let sameStreet = !buildingStreet.isEmpty && !featureStreet.isEmpty && buildingStreet == featureStreet
            let sameHouse = !buildingHouse.isEmpty && !featureHouse.isEmpty && buildingHouse == featureHouse

            let isPlausibleMatch =
                (sameStreet && sameHouse) ||
                (buildingStreet.isEmpty && centroidDistance <= min(polygonRadius + 8, 20))

            guard isPlausibleMatch else { return nil }

            let score =
                (sameStreet ? 120 : 0) +
                (sameHouse ? 40 : 0) -
                Int(min(centroidDistance.rounded(), 300))

            return AddressFeatureCandidate(feature: feature, score: score, distanceMeters: centroidDistance)
        }

        return sortedAddressCandidates(fallbackCandidates)
    }

    private func sortedAddressCandidates(_ candidates: [AddressFeatureCandidate]) -> [AddressFeature] {
        candidates
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.distanceMeters < $1.distanceMeters
            }
            .map(\.feature)
    }

    private func polygons(from geometry: MapFeatureGeoJSONGeometry) -> [Polygon] {
        if let rawPolygon = geometry.asPolygon {
            let ring = rawPolygon.first?.compactMap(makeCoordinate(from:)) ?? []
            if ring.count >= 3 {
                return [Polygon([ring])]
            }
        }

        if let rawMultiPolygon = geometry.asMultiPolygon {
            return rawMultiPolygon.compactMap { polygon in
                let ring = polygon.first?.compactMap(makeCoordinate(from:)) ?? []
                guard ring.count >= 3 else { return nil }
                return Polygon([ring])
            }
        }

        return []
    }

    private func coordinate(from geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        guard let point = geometry.asPoint, point.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
    }

    private func makeCoordinate(from raw: [Double]) -> CLLocationCoordinate2D? {
        guard raw.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: raw[1], longitude: raw[0])
    }

    private func approximatePolygonRadiusMeters(_ polygon: Polygon) -> Double? {
        guard let centroid = BuildingGeometryHelpers.polygonCentroid(polygon),
              let ring = polygon.coordinates.first,
              !ring.isEmpty else {
            return nil
        }

        let centroidLocation = CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)
        let maxDistance = ring.reduce(0.0) { partial, coordinate in
            let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return max(partial, centroidLocation.distance(from: point))
        }
        return maxDistance
    }

    private func normalizedStreetHint(for properties: BuildingProperties) -> String {
        if let streetName = normalizedStreetText(properties.streetName) {
            return streetName
        }
        return normalizedStreetText(properties.addressText) ?? ""
    }

    private func normalizedStreetHint(for properties: AddressProperties) -> String {
        if let streetName = normalizedStreetText(properties.streetName) {
            return streetName
        }
        return normalizedStreetText(properties.formatted) ?? ""
    }

    private func normalizedHouseHint(for properties: BuildingProperties) -> String {
        if let normalized = normalizedHouseText(properties.houseNumber) {
            return normalized
        }
        return normalizedHouseText(properties.addressText) ?? ""
    }

    private func normalizedHouseHint(for properties: AddressProperties) -> String {
        normalizedHouseText(properties.houseNumber) ?? normalizedHouseText(properties.formatted) ?? ""
    }

    private func normalizedStreetText(_ value: String?) -> String? {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let streetOnly = raw
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? raw

        let withoutHouseNumber = streetOnly.replacingOccurrences(
            of: #"^\s*\d+[A-Za-z\-]*\s+"#,
            with: "",
            options: .regularExpression
        )

        let normalized = withoutHouseNumber
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedHouseText(_ value: String?) -> String? {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let candidate = raw
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? raw

        guard let match = candidate.range(of: #"^\s*\d+[A-Za-z\-]*"#, options: .regularExpression) else {
            return nil
        }

        let normalized = candidate[match]
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)

        return normalized.isEmpty ? nil : normalized
    }

    private func loadLocalBuildingData(
        gersId: String,
        campaignId: UUID,
        addressId: UUID?,
        preferredAddressId: UUID?
    ) async -> BuildingData? {
        guard let localResolution = await resolveLocalAddressResolution(
            gersId: gersId,
            campaignId: campaignId,
            addressId: addressId
        ) else {
            return nil
        }
        let requestedAddressId = addressId?.uuidString.lowercased()
        let preferredAddressId = preferredAddressId?.uuidString.lowercased()
        let resolvedAddresses = localResolution.resolvedAddresses
        let primaryAddress = preferredAddressId.flatMap { preferred in
            resolvedAddresses.first(where: { $0.id.uuidString.lowercased() == preferred })
        } ?? requestedAddressId.flatMap { requested in
            resolvedAddresses.first(where: { $0.id.uuidString.lowercased() == requested })
        } ?? resolvedAddresses.first

        let residents: [Contact]
        let metadata: AddressCaptureMetadata?
        if let primaryAddress {
            residents = await ContactRepository.shared.fetchContactsForAddress(addressId: primaryAddress.id)
            metadata = await CampaignRepository.shared.getAddressCaptureMetadata(
                campaignId: campaignId,
                addressId: primaryAddress.id
            )
        } else {
            residents = []
            metadata = nil
        }

        let qrStatus: QRStatus
        if let buildingFeature = localResolution.buildingFeature {
            qrStatus = QRStatus(
                hasFlyer: buildingFeature.properties.scansTotal > 0 || (buildingFeature.properties.qrScanned ?? false),
                totalScans: buildingFeature.properties.scansTotal,
                lastScannedAt: nil
            )
        } else {
            qrStatus = .empty
        }

        let primaryResident = residents.first
        return BuildingData(
            isLoading: false,
            error: nil,
            address: primaryAddress,
            addresses: resolvedAddresses,
            residents: residents,
            qrStatus: qrStatus,
            buildingExists: localResolution.buildingFeature != nil || !resolvedAddresses.isEmpty,
            addressLinked: !resolvedAddresses.isEmpty,
            contactName: metadata?.contactName ?? primaryResident?.fullName,
            leadStatus: metadata?.leadStatus ?? primaryResident?.status.rawValue,
            productInterest: metadata?.productInterest,
            followUpDate: metadata?.followUpDate ?? primaryResident?.reminderDate,
            aiSummary: metadata?.aiSummary ?? metadata?.rawTranscript ?? primaryResident?.notes
        )
    }

    private func resolvedAddress(from feature: AddressFeature, fallbackGersId: String) -> ResolvedAddress? {
        let rawId = feature.properties.id ?? feature.id
        guard let rawId, let addressId = UUID(uuidString: rawId) else {
            return nil
        }

        let houseNumber = (feature.properties.houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetName = (feature.properties.streetName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let formatted = (feature.properties.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let street = [houseNumber, streetName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFormatted = !formatted.isEmpty ? formatted : street

        return ResolvedAddress(
            id: addressId,
            street: !street.isEmpty ? street : fallbackFormatted,
            formatted: fallbackFormatted,
            locality: feature.properties.locality ?? "",
            region: "",
            postalCode: feature.properties.postalCode ?? "",
            houseNumber: houseNumber,
            streetName: streetName,
            gersId: feature.properties.gersId ?? feature.properties.buildingGersId ?? fallbackGersId
        )
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
