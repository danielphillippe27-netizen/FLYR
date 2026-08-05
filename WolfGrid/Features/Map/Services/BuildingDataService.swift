import Foundation
import Supabase
import Combine
import CoreLocation

enum BuildingDataRemoteRefreshPolicy: Sendable {
    case immediate
    case backgroundIfStale
    case localOnly
}

/// Service for fetching and caching building data including address, residents, and QR status
@MainActor
class BuildingDataService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var buildingData: BuildingData = .empty
    
    // MARK: - Private Properties
    
    private let supabase: SupabaseClient
    private var cache: [String: CachedBuildingData] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    private let backgroundRefreshCooldown: TimeInterval = 120
    private var fetchGeneration = 0
    private var backgroundRefreshTasks: [String: Task<Void, Never>] = [:]
    private var lastBackgroundRefreshAt: [String: Date] = [:]
    private static let addressSelect = """
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
    """

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
    ///   - buildingIdentifiers: Additional public/row building IDs from the selected map feature.
    func fetchBuildingData(
        gersId: String,
        campaignId: UUID,
        addressId: UUID? = nil,
        preferredAddressId: UUID? = nil,
        addressTextHint: String? = nil,
        buildingIdentifiers: [String] = [],
        linkedAddressIds: [UUID] = [],
        remoteRefreshPolicy: BuildingDataRemoteRefreshPolicy = .immediate
    ) async {
        let trace = PerfTrace.begin("home_tap_card", "fetch_building_data", fields: [
            "campaign": campaignId.uuidString,
            "gers": gersId,
            "hasAddressId": addressId != nil,
            "linkedAddressIds": linkedAddressIds.count,
            "policy": "\(remoteRefreshPolicy)"
        ])
        fetchGeneration += 1
        let requestGeneration = fetchGeneration

        // Check cache first (include addressId when present so direct lookups are cached)
        let cacheKey = buildingDataCacheKey(
            gersId: gersId,
            campaignId: campaignId,
            addressId: addressId,
            buildingIdentifiers: buildingIdentifiers,
            linkedAddressIds: linkedAddressIds
        )
        if let cached = cache[cacheKey], cached.isValid(ttl: cacheTTL) {
            guard requestGeneration == fetchGeneration else {
                trace.end(status: "cancelled_after_cache_hit")
                return
            }
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
            trace.end(status: "cache_hit", fields: [
                "addresses": cached.data.addresses.count,
                "residents": cached.data.residents.count,
                "linked": cached.data.addressLinked
            ])
            return
        }

        let localTrace = PerfTrace.begin("home_tap_card", "load_local_building_data", fields: [
            "campaign": campaignId.uuidString,
            "gers": gersId,
            "hasAddressId": addressId != nil,
            "linkedAddressIds": linkedAddressIds.count
        ])
        let localData = await loadLocalBuildingData(
            gersId: gersId,
            campaignId: campaignId,
            addressId: addressId,
            preferredAddressId: preferredAddressId,
            buildingIdentifiers: buildingIdentifiers,
            linkedAddressIds: linkedAddressIds
        )
        localTrace.end(status: localData == nil ? "miss" : "hit", fields: [
            "addresses": localData?.addresses.count ?? 0,
            "residents": localData?.residents.count ?? 0,
            "linked": localData?.addressLinked ?? false
        ])
        guard requestGeneration == fetchGeneration else {
            trace.end(status: "cancelled_after_local")
            return
        }
        if let localData {
            buildingData = localData
            cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())

            switch remoteRefreshPolicy {
            case .backgroundIfStale:
                scheduleBackgroundRemoteRefresh(
                    cacheKey: cacheKey,
                    requestGeneration: requestGeneration,
                    gersId: gersId,
                    campaignId: campaignId,
                    addressId: addressId,
                    preferredAddressId: preferredAddressId,
                    addressTextHint: addressTextHint,
                    buildingIdentifiers: buildingIdentifiers,
                    linkedAddressIds: linkedAddressIds,
                    localData: localData
                )
                trace.end(status: "local_first_background_refresh", fields: [
                    "addresses": localData.addresses.count,
                    "residents": localData.residents.count,
                    "linked": localData.addressLinked
                ])
                return
            case .localOnly:
                trace.end(status: "local_only", fields: [
                    "addresses": localData.addresses.count,
                    "residents": localData.residents.count,
                    "linked": localData.addressLinked
                ])
                return
            case .immediate:
                break
            }
        } else {
            buildingData = .loading
        }

        if !NetworkMonitor.shared.isOnline {
            guard requestGeneration == fetchGeneration else {
                trace.end(status: "cancelled_offline")
                return
            }
            if let localData {
                buildingData = localData
                cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())
                trace.end(status: "offline_local", fields: [
                    "addresses": localData.addresses.count,
                    "residents": localData.residents.count,
                    "linked": localData.addressLinked
                ])
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
                trace.end(status: "offline_no_local")
            }
            return
        }

        do {
            let remoteTrace = PerfTrace.begin("home_tap_card", "fetch_remote_building_data", fields: [
                "campaign": campaignId.uuidString,
                "gers": gersId,
                "hasLocal": localData != nil
            ])
            let data = try await fetchRemoteBuildingData(
                gersId: gersId,
                campaignId: campaignId,
                addressId: addressId,
                preferredAddressId: preferredAddressId,
                addressTextHint: addressTextHint,
                buildingIdentifiers: buildingIdentifiers,
                linkedAddressIds: linkedAddressIds,
                localData: localData
            )
            remoteTrace.end(status: "success", fields: [
                "addresses": data.addresses.count,
                "residents": data.residents.count,
                "linked": data.addressLinked
            ])
            guard requestGeneration == fetchGeneration else {
                trace.end(status: "cancelled_after_remote")
                return
            }
            buildingData = data
            cache[cacheKey] = CachedBuildingData(data: data, timestamp: Date())
            trace.end(status: "remote_success", fields: [
                "addresses": data.addresses.count,
                "residents": data.residents.count,
                "linked": data.addressLinked
            ])
        } catch {
            PerfTrace.event("home_tap_card", "fetch_remote_building_data.error", fields: [
                "campaign": campaignId.uuidString,
                "gers": gersId,
                "error": error.localizedDescription
            ])
            if let localData = await loadLocalBuildingData(
                gersId: gersId,
                campaignId: campaignId,
                addressId: addressId,
                preferredAddressId: preferredAddressId,
                buildingIdentifiers: buildingIdentifiers,
                linkedAddressIds: linkedAddressIds
            ) {
                guard requestGeneration == fetchGeneration else {
                    trace.end(status: "cancelled_after_error_local")
                    return
                }
                buildingData = localData
                cache[cacheKey] = CachedBuildingData(data: localData, timestamp: Date())
                trace.end(status: "remote_error_local_fallback", fields: [
                    "addresses": localData.addresses.count,
                    "residents": localData.residents.count,
                    "linked": localData.addressLinked,
                    "error": error.localizedDescription
                ])
            } else {
                guard requestGeneration == fetchGeneration else {
                    trace.end(status: "cancelled_after_error")
                    return
                }
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
                trace.end(status: "remote_error_no_local", fields: [
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func buildingDataCacheKey(
        gersId: String,
        campaignId: UUID,
        addressId: UUID?,
        buildingIdentifiers: [String],
        linkedAddressIds: [UUID]
    ) -> String {
        let identifierCacheKey = Self.normalizedIdentifierList([gersId] + buildingIdentifiers).joined(separator: ",")
        let linkedAddressCacheKey = linkedAddressIds.map { $0.uuidString.lowercased() }.sorted().joined(separator: ",")
        if let addressId {
            return "\(campaignId.uuidString):addr:\(addressId.uuidString):\(identifierCacheKey):\(linkedAddressCacheKey)"
        }
        return "\(campaignId.uuidString):\(gersId):\(identifierCacheKey):\(linkedAddressCacheKey)"
    }

    private func scheduleBackgroundRemoteRefresh(
        cacheKey: String,
        requestGeneration: Int,
        gersId: String,
        campaignId: UUID,
        addressId: UUID?,
        preferredAddressId: UUID?,
        addressTextHint: String?,
        buildingIdentifiers: [String],
        linkedAddressIds: [UUID],
        localData: BuildingData
    ) {
        guard NetworkMonitor.shared.isOnline else {
            PerfTrace.event("home_tap_card", "background_remote_refresh.skip", fields: [
                "campaign": campaignId.uuidString,
                "gers": gersId,
                "reason": "offline"
            ])
            return
        }
        guard backgroundRefreshTasks[cacheKey] == nil else {
            PerfTrace.event("home_tap_card", "background_remote_refresh.skip", fields: [
                "campaign": campaignId.uuidString,
                "gers": gersId,
                "reason": "in_flight"
            ])
            return
        }
        if let lastRefresh = lastBackgroundRefreshAt[cacheKey],
           Date().timeIntervalSince(lastRefresh) < backgroundRefreshCooldown {
            PerfTrace.event("home_tap_card", "background_remote_refresh.skip", fields: [
                "campaign": campaignId.uuidString,
                "gers": gersId,
                "reason": "cooldown"
            ])
            return
        }

        PerfTrace.event("home_tap_card", "background_remote_refresh.scheduled", fields: [
            "campaign": campaignId.uuidString,
            "gers": gersId
        ])
        lastBackgroundRefreshAt[cacheKey] = Date()
        backgroundRefreshTasks[cacheKey] = Task { @MainActor in
            let trace = PerfTrace.begin("home_tap_card", "background_remote_refresh", fields: [
                "campaign": campaignId.uuidString,
                "gers": gersId
            ])
            defer { self.backgroundRefreshTasks[cacheKey] = nil }
            do {
                let data = try await self.fetchRemoteBuildingData(
                    gersId: gersId,
                    campaignId: campaignId,
                    addressId: addressId,
                    preferredAddressId: preferredAddressId,
                    addressTextHint: addressTextHint,
                    buildingIdentifiers: buildingIdentifiers,
                    linkedAddressIds: linkedAddressIds,
                    localData: localData
                )
                guard !Task.isCancelled, requestGeneration == self.fetchGeneration else {
                    trace.end(status: "cancelled")
                    return
                }
                self.buildingData = data
                self.cache[cacheKey] = CachedBuildingData(data: data, timestamp: Date())
                trace.end(status: "success", fields: [
                    "addresses": data.addresses.count,
                    "residents": data.residents.count,
                    "linked": data.addressLinked
                ])
            } catch {
                trace.end(status: "error", fields: [
                    "error": error.localizedDescription
                ])
                #if DEBUG
                print("⚠️ [BuildingDataService] Background card refresh skipped: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func fetchRemoteBuildingData(
        gersId: String,
        campaignId: UUID,
        addressId: UUID?,
        preferredAddressId: UUID?,
        addressTextHint: String?,
        buildingIdentifiers: [String],
        linkedAddressIds: [UUID],
        localData: BuildingData?
    ) async throws -> BuildingData {
        let decoder = JSONDecoder.supabaseDates
        var resolvedAddress: CampaignAddressResponse?
        var buildingExists = false
        var linkedPathAddresses: [CampaignAddressResponse] = []
        var goldPathAddresses: [CampaignAddressResponse] = []

        // Step 0: If we have address_id from the tapped feature, try direct lookup first (so we "have the link")
        if let addrId = addressId {
            let directQuery = supabase
                .from("campaign_addresses")
                .select(Self.addressSelect)
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
                .select(Self.addressSelect)
                .eq("campaign_id", value: campaignId.uuidString)
                .or(orFilter)

            let addressResponse = try await addressQuery.execute()
            let addresses = try decoder.decode([CampaignAddressResponse].self, from: addressResponse.data)
            linkedPathAddresses = addresses
            resolvedAddress = addresses.first
            buildingExists = resolvedAddress != nil
        }

        // Step 1b: Gold path — campaign_addresses.building_id = gers_id (ref_buildings_gold.id)
        if resolvedAddress == nil, UUID(uuidString: gersId) != nil {
            let goldQuery = supabase
                .from("campaign_addresses")
                .select(Self.addressSelect)
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

        let persistedLinkedAddresses = try await fetchPersistedLinkedAddresses(
            campaignId: campaignId,
            buildingIdentifiers: [gersId] + buildingIdentifiers,
            decoder: decoder
        )

        // Step 2: Build the card from persisted building links first, then fall back
        // to direct/gold/local geometry paths for legacy or partially cached data.
        var allAddressResponses: [CampaignAddressResponse] = []
        if allAddressResponses.isEmpty, !persistedLinkedAddresses.isEmpty {
            allAddressResponses = persistedLinkedAddresses
        }
        if allAddressResponses.isEmpty, !linkedAddressIds.isEmpty {
            let linkedIdStrings = linkedAddressIds.map(\.uuidString)
            let linkedAddressesResponse = try await supabase
                .from("campaign_addresses")
                .select(Self.addressSelect)
                .eq("campaign_id", value: campaignId.uuidString)
                .in("id", values: linkedIdStrings)
                .execute()
            allAddressResponses = try decoder.decode([CampaignAddressResponse].self, from: linkedAddressesResponse.data)
        }
        if allAddressResponses.isEmpty, !linkedPathAddresses.isEmpty {
            allAddressResponses = linkedPathAddresses
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
            addressId: addressId,
            preferredAddressId: preferredAddressId,
            buildingIdentifiers: buildingIdentifiers,
            linkedAddressIds: linkedAddressIds
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
        if Set(linkedAddressIds).count <= 1 {
            allAddressResponses = Self.addressesMatchingHintIfUnambiguous(
                allAddressResponses,
                addressTextHint: addressTextHint,
                preferredAddressId: preferredAddressId,
                requestedAddressId: addressId
            )
        }
        allAddressResponses = Self.enforceOneAddressPerBuilding(
            allAddressResponses,
            linkedAddressIds: linkedAddressIds,
            preferredAddressId: preferredAddressId,
            requestedAddressId: addressId
        )
        allAddressResponses = Self.sortAddressesForDisplay(allAddressResponses)
        if allAddressResponses.isEmpty {
            if let localData {
                return localData
            }
            if let loadedLocalData = await loadLocalBuildingData(
                gersId: gersId,
                campaignId: campaignId,
                addressId: addressId,
                preferredAddressId: preferredAddressId,
                buildingIdentifiers: buildingIdentifiers,
                linkedAddressIds: linkedAddressIds
            ) {
                return loadedLocalData
            }
        }
        await CampaignRepository.shared.upsertAddressCaptureMetadata(
            campaignId: campaignId,
            responses: allAddressResponses,
            dirty: false
        )
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
            return BuildingData(
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
        }

        return BuildingData(
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

    static func deduplicatedResolvedAddressesForDisplay(
        _ addresses: [ResolvedAddress],
        preferredAddressId: UUID? = nil,
        requestedAddressId: UUID? = nil
    ) -> [ResolvedAddress] {
        guard addresses.count > 1 else { return addresses }

        let priorityIds = Set([preferredAddressId, requestedAddressId].compactMap { $0 })
        var orderedKeys: [String] = []
        var keyedAddresses: [String: ResolvedAddress] = [:]

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

    private static func enforceOneAddressPerBuilding(
        _ addresses: [CampaignAddressResponse],
        linkedAddressIds: [UUID],
        preferredAddressId: UUID?,
        requestedAddressId: UUID?
    ) -> [CampaignAddressResponse] {
        guard addresses.count > 1 else { return addresses }

        let priorityIds = Set([preferredAddressId, requestedAddressId].compactMap { $0 })
        if !priorityIds.isEmpty {
            let priorityMatches = addresses.filter { priorityIds.contains($0.id) }
            if !priorityMatches.isEmpty {
                return priorityMatches
            }
        }

        let explicitLinkedIds = Set(linkedAddressIds)
        if explicitLinkedIds.count == 1,
           let onlyLinkedId = explicitLinkedIds.first,
           let linkedAddress = addresses.first(where: { $0.id == onlyLinkedId }) {
            return [linkedAddress]
        }
        if explicitLinkedIds.count > 1 {
            let linkedAddresses = addresses.filter { explicitLinkedIds.contains($0.id) }
            if !linkedAddresses.isEmpty {
                return linkedAddresses
            }
        }

        let labels = addresses
            .prefix(6)
            .map { ($0.formatted ?? "\($0.houseNumber ?? "") \($0.streetName ?? "")").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        print("⚠️ [BuildingDataService] Suppressed \(addresses.count) addresses for one building: \(labels)")
        return []
    }
    /// Fetches contacts for a given address ID
    /// - Parameter addressId: The address ID to fetch contacts for
    /// - Returns: Array of contacts
    private func fetchContactsForAddress(addressId: UUID) async throws -> [Contact] {
        let trace = PerfTrace.begin("home_tap_card", "fetch_contacts", fields: [
            "address": addressId.uuidString
        ])
        let cached = await ContactRepository.shared.fetchContactsForAddress(addressId: addressId)
        guard NetworkMonitor.shared.isOnline else {
            trace.end(status: "offline_cache", fields: [
                "contacts": cached.count
            ])
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
            trace.end(status: "remote_success", fields: [
                "contacts": remote.count,
                "cachedContacts": cached.count
            ])
            return remote
        } catch {
            if !cached.isEmpty {
                trace.end(status: "remote_error_cache_fallback", fields: [
                    "contacts": cached.count,
                    "error": error.localizedDescription
                ])
                return cached
            }
            trace.end(status: "remote_error", fields: [
                "error": error.localizedDescription
            ])
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

    private static func normalizedStreetName(for address: ResolvedAddress) -> String {
        let explicitStreet = address.streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitStreet.isEmpty {
            return explicitStreet
        }

        let street = address.street.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = !street.isEmpty ? street : address.formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = source.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? source
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
        let primary = [house, normalizedStreetIdentityPart(street)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !primary.isEmpty {
            return primary
        }

        let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        let fallback = normalizedStreetIdentityPart(streetOnly)
        return fallback.isEmpty ? address.id.uuidString.lowercased() : fallback
    }

    private static func normalizedAddressIdentity(for address: ResolvedAddress) -> String {
        let house = normalizedHouseNumberIdentity(for: address)
        let street = normalizedStreetName(for: address)
        let primary = [house, normalizedStreetIdentityPart(street)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !primary.isEmpty {
            return primary
        }

        let formatted = address.formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        let fallback = normalizedStreetIdentityPart(streetOnly)
        return fallback.isEmpty ? address.id.uuidString.lowercased() : fallback
    }

    private static func normalizedAddressIdentity(fromText value: String?) -> String? {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let streetOnly = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? raw
        let parts = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return normalizedAddressPart(streetOnly) }

        let house = normalizedAddressPart(String(first))
        let street = parts.count > 1 ? normalizedStreetIdentityPart(String(parts[1])) : ""
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

    private static func normalizedHouseNumberIdentity(for address: ResolvedAddress) -> String {
        let explicitHouse = address.houseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitHouse.isEmpty {
            return normalizedAddressPart(explicitHouse)
        }

        let street = address.street.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = !street.isEmpty ? street : address.formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = source.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? source
        let house = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return normalizedAddressPart(house)
    }

    private static func normalizedAddressPart(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedStreetIdentityPart(_ value: String?) -> String {
        normalizedAddressPart(value)
            .split(separator: " ")
            .map { word -> String in
                switch word {
                case "st", "str": return "street"
                case "rd": return "road"
                case "ave", "av": return "avenue"
                case "blvd": return "boulevard"
                case "dr": return "drive"
                case "ct", "crt": return "court"
                case "cres": return "crescent"
                case "ln": return "lane"
                case "pl": return "place"
                case "trl": return "trail"
                case "pkwy": return "parkway"
                case "hwy": return "highway"
                default: return String(word)
                }
            }
            .joined(separator: " ")
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

    private static func normalizedIdentifierList(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private struct PersistedBuildingAddressLinkRow: Decodable {
        let addressId: String

        enum CodingKeys: String, CodingKey {
            case addressId = "address_id"
        }
    }

    private struct PersistedBuildingIdentityRow: Decodable {
        let id: String
        let gersId: String?

        enum CodingKeys: String, CodingKey {
            case id
            case gersId = "gers_id"
        }
    }

    private func fetchPersistedLinkedAddresses(
        campaignId: UUID,
        buildingIdentifiers: [String],
        decoder: JSONDecoder
    ) async throws -> [CampaignAddressResponse] {
        let identifiers = Self.normalizedIdentifierList(buildingIdentifiers)
        guard !identifiers.isEmpty else { return [] }

        var buildingRowIds = Set(
            identifiers.compactMap { identifier -> String? in
                UUID(uuidString: identifier)?.uuidString.lowercased()
            }
        )
        var directBuildingIdentifiers = Set(identifiers)

        if !buildingRowIds.isEmpty {
            let rowsResponse = try await supabase
                .from("buildings")
                .select("id, gers_id")
                .eq("campaign_id", value: campaignId.uuidString)
                .in("id", values: Array(buildingRowIds))
                .execute()
            let rows = try decoder.decode([PersistedBuildingIdentityRow].self, from: rowsResponse.data)
            buildingRowIds.formUnion(rows.map { $0.id.lowercased() })
            directBuildingIdentifiers.formUnion(rows.compactMap { $0.gersId?.lowercased() })
        }

        let gersResponse = try await supabase
            .from("buildings")
            .select("id, gers_id")
            .eq("campaign_id", value: campaignId.uuidString)
            .in("gers_id", values: identifiers)
            .execute()
        let gersRows = try decoder.decode([PersistedBuildingIdentityRow].self, from: gersResponse.data)
        buildingRowIds.formUnion(gersRows.map { $0.id.lowercased() })
        directBuildingIdentifiers.formUnion(buildingRowIds)
        directBuildingIdentifiers.formUnion(gersRows.compactMap { $0.gersId?.lowercased() })

        var linkedAddressIds: [String] = []
        if !buildingRowIds.isEmpty {
            let linksResponse = try await supabase
                .from("building_address_links")
                .select("address_id")
                .eq("campaign_id", value: campaignId.uuidString)
                .in("building_id", values: Array(buildingRowIds))
                .execute()
            let links = try decoder.decode([PersistedBuildingAddressLinkRow].self, from: linksResponse.data)
            linkedAddressIds.append(contentsOf: Self.normalizedIdentifierList(links.map(\.addressId)))
        }

        var addressRowsById: [UUID: CampaignAddressResponse] = [:]
        if !linkedAddressIds.isEmpty {
            let addressesResponse = try await supabase
                .from("campaign_addresses")
                .select(Self.addressSelect)
                .eq("campaign_id", value: campaignId.uuidString)
                .in("id", values: linkedAddressIds)
                .execute()
            for address in try decoder.decode([CampaignAddressResponse].self, from: addressesResponse.data) {
                addressRowsById[address.id] = address
            }
        }

        if !directBuildingIdentifiers.isEmpty {
            let directValues = Array(directBuildingIdentifiers)
            let directGersResponse = try await supabase
                .from("campaign_addresses")
                .select(Self.addressSelect)
                .eq("campaign_id", value: campaignId.uuidString)
                .in("building_gers_id", values: directValues)
                .execute()
            for address in try decoder.decode([CampaignAddressResponse].self, from: directGersResponse.data) {
                addressRowsById[address.id] = address
            }
        }

        let uuidDirectValues = Array(
            directBuildingIdentifiers.compactMap { UUID(uuidString: $0)?.uuidString.lowercased() }
        )
        if !uuidDirectValues.isEmpty {
            let directBuildingIdResponse = try await supabase
                .from("campaign_addresses")
                .select(Self.addressSelect)
                .eq("campaign_id", value: campaignId.uuidString)
                .in("building_id", values: uuidDirectValues)
                .execute()
            for address in try decoder.decode([CampaignAddressResponse].self, from: directBuildingIdResponse.data) {
                addressRowsById[address.id] = address
            }
        }

        return Self.sortAddressesForDisplay(Array(addressRowsById.values))
    }

    private struct LocalAddressResolution {
        let buildingFeature: BuildingFeature?
        let resolvedAddresses: [ResolvedAddress]
        let matchedAddressIDs: Set<UUID>
    }

    private func resolveLocalAddressResolution(
        gersId: String,
        campaignId: UUID,
        addressId: UUID?,
        preferredAddressId: UUID? = nil,
        buildingIdentifiers: [String] = [],
        linkedAddressIds: [UUID] = []
    ) async -> LocalAddressResolution? {
        guard let bundle = await CampaignRepository.shared.getCampaignMapBundle(campaignId: campaignId.uuidString) else {
            return nil
        }

        let normalizedIdentifiers = Set(Self.normalizedIdentifierList([gersId] + buildingIdentifiers))
        let buildingFeature = bundle.buildings.features.first { feature in
            if let featureId = feature.id?.lowercased(), normalizedIdentifiers.contains(featureId) {
                return true
            }
            return feature.properties.buildingIdentifierCandidates.contains(where: { normalizedIdentifiers.contains($0.lowercased()) })
        }

        var buildingCandidates = normalizedIdentifiers
        if let buildingFeature {
            buildingCandidates.formUnion(buildingFeature.properties.buildingIdentifierCandidates.map { $0.lowercased() })
        }

        var explicitAddressIds = Set<String>()
        if let directAddressId = buildingFeature?.properties.addressId?.lowercased() {
            explicitAddressIds.insert(directAddressId)
        }
        if let requestedAddressId = addressId?.uuidString.lowercased() {
            explicitAddressIds.insert(requestedAddressId)
        }
        explicitAddressIds.formUnion(linkedAddressIds.map { $0.uuidString.lowercased() })

        let explicitMatches = bundle.addresses.features.filter { feature in
            let featureAddressId = (feature.properties.id ?? feature.id)?.lowercased()
            if let featureAddressId, explicitAddressIds.contains(featureAddressId) {
                return true
            }
            return false
        }

        let persistedBuildingMatches = bundle.addresses.features.filter { feature in
            let addressBuildingIdentifiers = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            return addressBuildingIdentifiers.contains(where: { buildingCandidates.contains($0) })
        }

        let matchedFeatures: [AddressFeature]
        if addressId != nil, !explicitMatches.isEmpty {
            matchedFeatures = explicitMatches
        } else if !persistedBuildingMatches.isEmpty {
            matchedFeatures = persistedBuildingMatches
        } else if buildingFeature != nil {
            // Only persisted address/building assignments may populate a home.
            // Geometry can overlap row-home address points, so display-time spatial inference
            // would create hidden links that were never saved by campaign provisioning.
            matchedFeatures = explicitMatches
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
        resolvedAddresses = Self.deduplicatedResolvedAddressesForDisplay(
            resolvedAddresses,
            preferredAddressId: preferredAddressId,
            requestedAddressId: addressId
        )
        resolvedAddresses.sort { lhs, rhs in
            lhs.displayStreet.localizedStandardCompare(rhs.displayStreet) == .orderedAscending
        }

        return LocalAddressResolution(
            buildingFeature: buildingFeature,
            resolvedAddresses: resolvedAddresses,
            matchedAddressIDs: Set(resolvedAddresses.map { $0.id })
        )
    }

    private func loadLocalBuildingData(
        gersId: String,
        campaignId: UUID,
        addressId: UUID?,
        preferredAddressId: UUID?,
        buildingIdentifiers: [String] = [],
        linkedAddressIds: [UUID] = []
    ) async -> BuildingData? {
        guard let localResolution = await resolveLocalAddressResolution(
            gersId: gersId,
            campaignId: campaignId,
            addressId: addressId,
            preferredAddressId: preferredAddressId,
            buildingIdentifiers: buildingIdentifiers,
            linkedAddressIds: linkedAddressIds
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
        let campaignPrefix = "\(campaignId.uuidString):"
        let normalizedGersId = gersId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedGersId.isEmpty else { return }
        cache = cache.filter { key, _ in
            guard key.hasPrefix(campaignPrefix) else { return true }
            return !key.lowercased().contains(normalizedGersId)
        }
    }
    
    /// Clears the cache entry for a specific address (used when address-linked data changes, e.g. new resident)
    func clearCacheEntry(addressId: UUID, campaignId: UUID) {
        let addressPrefix = "\(campaignId.uuidString):addr:\(addressId.uuidString)"
        let normalizedAddressId = addressId.uuidString.lowercased()
        cache = cache.filter { key, _ in
            let lowercasedKey = key.lowercased()
            return !key.hasPrefix(addressPrefix) && !lowercasedKey.contains(normalizedAddressId)
        }
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
