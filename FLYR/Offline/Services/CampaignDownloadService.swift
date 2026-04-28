import Foundation
import CoreLocation
import Combine
import Supabase
import PostgREST

struct CampaignOfflineReadiness: Equatable, Sendable {
    let campaignId: String
    let isVerified: Bool
    let missingComponents: [String]
    let buildingsCount: Int
    let addressesCount: Int
    let contactsCount: Int
    let activitiesCount: Int
    let statusesCount: Int
    let roadsCount: Int
    let mapTilesReady: Bool

    var summary: String {
        if isVerified {
            return "Local data ready: \(addressesCount) homes, \(contactsCount) contacts, \(activitiesCount) activity items, and map tiles are stored on this device."
        }
        if missingComponents.isEmpty {
            return "Local data is still being verified."
        }
        return "Local data needs attention: missing \(missingComponents.joined(separator: ", "))."
    }
}

@MainActor
final class CampaignDownloadService: ObservableObject {
    static let shared = CampaignDownloadService()

    @Published private(set) var states: [String: CampaignDownloadState] = [:]
    @Published private(set) var readiness: [String: CampaignOfflineReadiness] = [:]

    private let campaignRepository = CampaignRepository.shared
    private let supabase = SupabaseClientShim()
    private var activeDownloads = Set<String>()

    private init() {}

    func state(for campaignId: String) -> CampaignDownloadState? {
        states[campaignId]
    }

    func readiness(for campaignId: String) -> CampaignOfflineReadiness? {
        readiness[campaignId]
    }

    func refreshState(campaignId: String) async {
        states[campaignId] = await campaignRepository.getDownloadState(campaignId: campaignId)
        readiness[campaignId] = await computeReadiness(campaignId: campaignId)
    }

    func recordSuccessfulSync(campaignId: String, at date: Date = Date()) async {
        await campaignRepository.markCampaignLastSynced(campaignId: campaignId, at: date)
        await refreshState(campaignId: campaignId)
    }

    func prefetchIfNeeded(campaignId: String) async {
        await refreshState(campaignId: campaignId)
        guard NetworkMonitor.shared.isOnline else { return }
        if activeDownloads.contains(campaignId) { return }
        let existingState = if let cachedState = states[campaignId] {
            cachedState
        } else {
            await campaignRepository.getDownloadState(campaignId: campaignId)
        }

        if let existingState,
           existingState.isAvailableOffline || existingState.status == "downloading" {
            states[campaignId] = existingState
            return
        }

        await makeAvailableOffline(campaignId: campaignId)
    }

    func makeAvailableOffline(campaignId: String) async {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        guard !activeDownloads.contains(campaignId) else {
            await refreshState(campaignId: campaignId)
            return
        }

        activeDownloads.insert(campaignId)
        defer { activeDownloads.remove(campaignId) }

        let startedAt = Date()
        await campaignRepository.updateDownloadState(
            campaignId: campaignId,
            status: "downloading",
            progress: 0.05,
            startedAt: startedAt
        )
        await refreshState(campaignId: campaignId)

        do {
            let metadata = try await fetchCampaignMetadata(campaignId: campaignUUID)
            await campaignRepository.upsertCampaign(
                id: campaignId,
                name: metadata.name,
                mode: metadata.mode,
                boundaryGeoJSON: metadata.boundaryGeoJSON,
                payloadJSON: metadata.payloadJSON,
                downloadedAt: nil
            )

            let buildings = try await BuildingLinkService.shared.fetchBuildings(campaignId: campaignId)
            await campaignRepository.upsertBuildings(campaignId: campaignId, features: buildings)
            await campaignRepository.updateDownloadState(campaignId: campaignId, status: "downloading", progress: 0.30, startedAt: startedAt)

            let addresses = try await fetchAddresses(campaignId: campaignUUID)
            await campaignRepository.upsertAddresses(campaignId: campaignId, features: addresses.features)
            await campaignRepository.updateDownloadState(campaignId: campaignId, status: "downloading", progress: 0.55, startedAt: startedAt)

            let addressMetadata = try await fetchCampaignAddressMetadata(campaignId: campaignUUID)
            await campaignRepository.upsertAddressCaptureMetadata(
                campaignId: campaignUUID,
                responses: addressMetadata,
                dirty: false
            )

            let links = try await BuildingLinkService.shared.fetchLinks(campaignId: campaignId)
            await campaignRepository.upsertBuildingAddressLinks(campaignId: campaignId, links: links)

            let statuses = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignUUID, forceRefresh: true)
            await campaignRepository.upsertStatuses(rows: Array(statuses.values))
            await campaignRepository.updateDownloadState(campaignId: campaignId, status: "downloading", progress: 0.80, startedAt: startedAt)

            let contacts = try await fetchCampaignContacts(campaignId: campaignUUID)
            await ContactRepository.shared.upsertContacts(contacts, userId: nil, workspaceId: nil, dirty: false, syncedAt: Date())

            let contactActivities = try await fetchCampaignContactActivities(contactIds: contacts.map(\.id))
            await ContactRepository.shared.upsertActivities(contactActivities, dirty: false, syncedAt: Date())

            let corridors = await CampaignRoadService.shared.getRoadsForSession(campaignId: campaignId)
            await campaignRepository.upsertRoads(campaignId: campaignId, corridors: corridors)

            setTransientState(
                campaignId: campaignId,
                status: "downloading",
                progress: 0.82,
                startedAt: startedAt,
                errorMessage: nil
            )

            try await MapboxOfflineService.shared.downloadCampaignRegion(
                campaignId: campaignId,
                boundaryGeoJSON: metadata.boundaryGeoJSON,
                addresses: addresses.features,
                onProgress: { [weak self] progress in
                    self?.setTransientState(
                        campaignId: campaignId,
                        status: "downloading",
                        progress: min(max(0.82 + (progress * 0.18), 0.82), 0.99),
                        startedAt: startedAt,
                        errorMessage: nil
                    )
                }
            )

            let readiness = await computeReadiness(
                campaignId: campaignId,
                expected: OfflineExpectedCounts(
                    buildings: buildings.count,
                    addresses: addresses.features.count,
                    buildingLinks: links.count,
                    statuses: statuses.count,
                    roads: corridors.count,
                    metadata: addressMetadata.count,
                    contacts: contacts.count,
                    activities: contactActivities.count
                ),
                mapTilesReady: true
            )
            self.readiness[campaignId] = readiness
            guard readiness.isVerified else {
                throw CampaignOfflineVerificationError.verificationFailed(readiness.missingComponents)
            }

            let completedAt = Date()
            await campaignRepository.updateDownloadState(
                campaignId: campaignId,
                status: "ready",
                progress: 1,
                startedAt: startedAt,
                completedAt: completedAt,
                lastSyncedAt: completedAt
            )
        } catch {
            await campaignRepository.updateDownloadState(
                campaignId: campaignId,
                status: "failed",
                progress: 0,
                startedAt: startedAt,
                errorMessage: error.localizedDescription
            )
        }

        await refreshState(campaignId: campaignId)
    }

    private func setTransientState(
        campaignId: String,
        status: String,
        progress: Double,
        startedAt: Date?,
        errorMessage: String?
    ) {
        let existing = states[campaignId]
        states[campaignId] = CampaignDownloadState(
            campaignId: campaignId,
            status: status,
            progress: progress,
            startedAt: startedAt ?? existing?.startedAt,
            completedAt: existing?.completedAt,
            errorMessage: errorMessage,
            lastSyncedAt: existing?.lastSyncedAt
        )
    }

    private func fetchAddresses(campaignId: UUID) async throws -> AddressFeatureCollection {
        let data = try await supabase.callRPCData(
            "rpc_get_campaign_addresses",
            params: ["p_campaign_id": campaignId.uuidString]
        )
        return try JSONDecoder().decode(AddressFeatureCollection.self, from: data)
    }

    private func fetchCampaignAddressMetadata(campaignId: UUID) async throws -> [CampaignAddressResponse] {
        let response = try await SupabaseManager.shared.client
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
            .execute()

        return try JSONDecoder.supabaseDates.decode([CampaignAddressResponse].self, from: response.data)
    }

    private func fetchCampaignContacts(campaignId: UUID) async throws -> [Contact] {
        let response = try await SupabaseManager.shared.client
            .from("contacts")
            .select("*")
            .eq("campaign_id", value: campaignId.uuidString)
            .order("updated_at", ascending: false)
            .execute()

        return try JSONDecoder.supabaseDates.decode([Contact].self, from: response.data)
    }

    private func fetchCampaignContactActivities(contactIds: [UUID]) async throws -> [ContactActivity] {
        let uniqueContactIds = Array(Set(contactIds))
        guard !uniqueContactIds.isEmpty else { return [] }

        var allActivities: [ContactActivity] = []
        for batch in uniqueContactIds.chunked(into: 100) {
            let response = try await SupabaseManager.shared.client
                .from("contact_activities")
                .select("*")
                .in("contact_id", values: batch.map(\.uuidString))
                .order("timestamp", ascending: false)
                .execute()
            let activities = try JSONDecoder.supabaseDates.decode([ContactActivity].self, from: response.data)
            allActivities.append(contentsOf: activities)
        }

        return allActivities
    }

    private func computeReadiness(
        campaignId: String,
        expected: OfflineExpectedCounts? = nil,
        mapTilesReady: Bool? = nil
    ) async -> CampaignOfflineReadiness {
        let assetCounts = await campaignRepository.getOfflineAssetCounts(campaignId: campaignId)
        let contactCounts = await ContactRepository.shared.getOfflineCounts(campaignId: UUID(uuidString: campaignId) ?? UUID())
        let currentState = if let cachedState = states[campaignId] {
            cachedState
        } else {
            await campaignRepository.getDownloadState(campaignId: campaignId)
        }
        let resolvedMapTilesReady = mapTilesReady ?? currentState?.isAvailableOffline == true

        let requiredAddresses = expected?.addresses ?? max(assetCounts.addresses, 0)
        let requiredBuildings = expected?.buildings ?? max(assetCounts.buildings, 0)
        let requiredLinks = expected?.buildingLinks ?? (requiredAddresses > 0 ? assetCounts.buildingLinks : 0)
        let requiredMetadata = expected?.metadata ?? requiredAddresses
        let requiredStatuses = expected?.statuses ?? assetCounts.statuses
        let requiredRoads = expected?.roads ?? assetCounts.roads
        let requiredContacts = expected?.contacts ?? contactCounts.contacts
        let requiredActivities = expected?.activities ?? contactCounts.activities

        var missing: [String] = []
        if !resolvedMapTilesReady { missing.append("map tiles") }
        if assetCounts.buildings < requiredBuildings || assetCounts.buildings == 0 { missing.append("buildings") }
        if assetCounts.addresses < requiredAddresses || assetCounts.addresses == 0 { missing.append("addresses") }
        if assetCounts.buildingLinks < requiredLinks { missing.append("building links") }
        if assetCounts.metadata < requiredMetadata { missing.append("address notes") }
        if assetCounts.statuses < requiredStatuses { missing.append("visit statuses") }
        if assetCounts.roads < requiredRoads { missing.append("roads") }
        if contactCounts.contacts < requiredContacts { missing.append("contacts") }
        if contactCounts.activities < requiredActivities { missing.append("contact history") }

        return CampaignOfflineReadiness(
            campaignId: campaignId,
            isVerified: missing.isEmpty,
            missingComponents: missing,
            buildingsCount: assetCounts.buildings,
            addressesCount: assetCounts.addresses,
            contactsCount: contactCounts.contacts,
            activitiesCount: contactCounts.activities,
            statusesCount: assetCounts.statuses,
            roadsCount: assetCounts.roads,
            mapTilesReady: resolvedMapTilesReady
        )
    }

    private func fetchCampaignMetadata(campaignId: UUID) async throws -> (name: String?, mode: String?, boundaryGeoJSON: String?, payloadJSON: String?) {
        let response = try await SupabaseManager.shared.client
            .from("campaigns")
            .select("id,title,status,territory_boundary")
            .eq("id", value: campaignId.uuidString)
            .single()
            .execute()

        let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
        let title = object?["title"] as? String
        let status = object?["status"] as? String
        let boundaryObject = object?["territory_boundary"]
        let boundaryGeoJSON: String?
        if let boundaryObject,
           JSONSerialization.isValidJSONObject(boundaryObject),
           let data = try? JSONSerialization.data(withJSONObject: boundaryObject, options: [.sortedKeys]) {
            boundaryGeoJSON = String(data: data, encoding: .utf8)
        } else {
            boundaryGeoJSON = nil
        }

        let payloadJSON: String?
        if let object, JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            payloadJSON = String(data: data, encoding: .utf8)
        } else {
            payloadJSON = nil
        }

        return (title, status, boundaryGeoJSON, payloadJSON)
    }
}

private struct OfflineExpectedCounts {
    let buildings: Int
    let addresses: Int
    let buildingLinks: Int
    let statuses: Int
    let roads: Int
    let metadata: Int
    let contacts: Int
    let activities: Int
}

private enum CampaignOfflineVerificationError: LocalizedError {
    case verificationFailed([String])

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let missing):
            return "Offline verification failed: missing \(missing.joined(separator: ", "))."
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }
        return chunks
    }
}
