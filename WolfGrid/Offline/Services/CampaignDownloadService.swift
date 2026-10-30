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
            return "\(addressesCount) homes + map tiles saved on this device."
        }
        if missingComponents.isEmpty {
            return "Offline data is still being verified."
        }
        return "Offline data needs attention: missing \(missingComponents.joined(separator: ", "))."
    }
}

struct CampaignMapAssetReadiness: Equatable, Sendable {
    let campaignId: String
    let isMapReady: Bool
    let missingComponents: [String]
    let buildingsCount: Int
    let addressesCount: Int
    let linksCount: Int
    let roadsCount: Int
    let hasLinkedAddressIdentity: Bool
    let progressPercent: Int

    var isMapUsable: Bool {
        isMapReady || buildingsCount > 0 || addressesCount > 0
    }

    var summary: String {
        if isMapReady {
            return "\(addressesCount) homes + \(buildingsCount) buildings saved for the map."
        }
        if missingComponents.isEmpty {
            return "Campaign map is still being verified."
        }
        return "Campaign map needs \(missingComponents.joined(separator: ", "))."
    }
}

enum OfflineCapabilityState: Equatable, Sendable {
    case availableOffline
    case syncPending(pendingCount: Int)
    case refreshing
    case onlineOnly(reason: String)
    case missingCache(reason: String)

    var userMessage: String {
        switch self {
        case .availableOffline:
            return "Available offline"
        case .syncPending(let pendingCount):
            return "\(pendingCount) changes waiting to sync"
        case .refreshing:
            return "Refreshing in the background"
        case .onlineOnly(let reason), .missingCache(let reason):
            return reason
        }
    }
}

struct OfflinePreloadCandidate: Equatable, Sendable {
    let campaignId: UUID
    let priority: Int
    let reason: String
}

enum OfflinePreloadSelector {
    static func selectCandidates(
        assignedCampaignIds: [UUID],
        recentCampaignIds: [UUID],
        inProgressFarmCampaignIds: [UUID]
    ) -> [OfflinePreloadCandidate] {
        var bestByCampaignId: [UUID: OfflinePreloadCandidate] = [:]
        func add(_ campaignId: UUID, priority: Int, reason: String) {
            let candidate = OfflinePreloadCandidate(campaignId: campaignId, priority: priority, reason: reason)
            if let existing = bestByCampaignId[campaignId], existing.priority >= priority {
                return
            }
            bestByCampaignId[campaignId] = candidate
        }

        assignedCampaignIds.forEach { add($0, priority: 300, reason: "assigned_route") }
        inProgressFarmCampaignIds.forEach { add($0, priority: 200, reason: "in_progress_farm") }
        recentCampaignIds.forEach { add($0, priority: 100, reason: "recent_campaign") }

        return bestByCampaignId.values.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.campaignId.uuidString < $1.campaignId.uuidString
        }
    }
}

@MainActor
final class CampaignDownloadService: ObservableObject {
    static let shared = CampaignDownloadService()
    private static let pageSize = 1_000

    @Published private(set) var states: [String: CampaignDownloadState] = [:]
    @Published private(set) var mapTileBytes: [String: UInt64] = [:]
    @Published private(set) var readiness: [String: CampaignOfflineReadiness] = [:]
    @Published private(set) var mapAssetReadiness: [String: CampaignMapAssetReadiness] = [:]

    private let campaignRepository = CampaignRepository.shared
    private var activeDownloads = Set<String>()
    private var activeMapAssetDownloads = Set<String>()
    private var refreshVersions: [String: UInt64] = [:]

    private init() {}

    func state(for campaignId: String) -> CampaignDownloadState? {
        states[campaignId]
    }

    func readiness(for campaignId: String) -> CampaignOfflineReadiness? {
        readiness[campaignId]
    }

    func mapReadiness(for campaignId: String) -> CampaignMapAssetReadiness? {
        mapAssetReadiness[campaignId]
    }

    func refreshState(campaignId: String) async {
        let version = (refreshVersions[campaignId] ?? 0) &+ 1
        refreshVersions[campaignId] = version
        var state = await campaignRepository.getDownloadState(campaignId: campaignId)
        let interrupted = state?.status == "downloading" && !activeDownloads.contains(campaignId)
        let existingTilesReady = interrupted
            ? await MapboxOfflineService.shared.hasCompleteCampaignRegion(campaignId: campaignId)
            : nil
        let currentReadiness = await computeReadiness(campaignId: campaignId, mapTilesReady: existingTilesReady)
        if state?.status == "downloading", !activeDownloads.contains(campaignId) {
            state = await campaignRepository.getDownloadState(campaignId: campaignId)
        }
        // A process termination can leave a persisted downloading state behind.
        // Restore the verified package or offer a retry when no task owns it.
        if state?.status == "downloading", !activeDownloads.contains(campaignId) {
            let ready = currentReadiness.isVerified
            await campaignRepository.updateDownloadState(
                campaignId: campaignId,
                status: ready ? "ready" : "failed",
                progress: ready ? 1 : 0,
                startedAt: state?.startedAt,
                completedAt: ready ? (state?.completedAt ?? Date()) : nil,
                errorMessage: ready ? nil : "Download was interrupted. Tap Retry to continue.",
                lastSyncedAt: state?.lastSyncedAt
            )
            state = await campaignRepository.getDownloadState(campaignId: campaignId)
        }
        let tileBytes = await MapboxOfflineService.shared.campaignRegionStorageBytes(campaignId: campaignId)
        let assetReadiness = await computeMapAssetReadiness(campaignId: campaignId)
        // Async checks can overlap a later refresh or the download finishing.
        // Publish the latest persisted status only, never an older snapshot.
        state = await campaignRepository.getDownloadState(campaignId: campaignId)
        guard refreshVersions[campaignId] == version else { return }
        states[campaignId] = state
        readiness[campaignId] = currentReadiness
        mapTileBytes[campaignId] = tileBytes
        mapAssetReadiness[campaignId] = assetReadiness
    }

    func refreshMapAssetReadiness(campaignId: String) async {
        mapAssetReadiness[campaignId] = await computeMapAssetReadiness(campaignId: campaignId)
    }

    func recordSuccessfulSync(campaignId: String, at date: Date = Date()) async {
        await campaignRepository.markCampaignLastSynced(campaignId: campaignId, at: date)
        await refreshState(campaignId: campaignId)
    }

    /// Warm only the map shown in the campaign picker. Contacts, activity history,
    /// and offline tile packs are left to the existing full-download coordinator.
    func prefetchMapBundleIfNeeded(campaignId: String) async {
        guard OfflineFirstConfig.isEnabled,
              !Task.isCancelled,
              NetworkMonitor.shared.isOnline,
              !NetworkMonitor.shared.isCellular || OfflineFirstConfig.cellularPreloadAllowed,
              let userId = AuthManager.shared.user?.id else { return }
        let workspaceId = WorkspaceContext.shared.workspaceId
        guard !(await campaignRepository.hasCampaignMapBundle(campaignId: campaignId)),
              !Task.isCancelled else { return }

        let trace = PerfTrace.begin("campaign_open", "visible_map_prefetch", fields: ["campaign": campaignId])
        do {
            // Uses the same request deduper as foreground map opening.
            let result = try await BuildingLinkService.shared.fetchCanonicalCampaignMapBundle(
                campaignId: campaignId,
                localSignature: nil
            )
            guard !Task.isCancelled,
                  AuthManager.shared.user?.id == userId,
                  WorkspaceContext.shared.workspaceId == workspaceId else {
                trace.end(status: "cancelled_or_scope_changed")
                return
            }
            guard case .bundle(let bundle) = result else {
                trace.end(status: "not_modified")
                return
            }
            // Another downloader may have saved the same coalesced response already.
            guard !(await campaignRepository.hasCampaignMapBundle(campaignId: campaignId)),
                  !Task.isCancelled,
                  AuthManager.shared.user?.id == userId,
                  WorkspaceContext.shared.workspaceId == workspaceId else {
                trace.end(status: "already_cached_or_cancelled")
                return
            }
            let persisted = await campaignRepository.replaceCampaignMapBundle(campaignId: campaignId, bundle: bundle)
            trace.end(status: persisted ? "ready" : "persist_failed", fields: [
                "addresses": bundle.addresses.features.count,
                "buildings": bundle.buildings.features.count
            ])
        } catch {
            trace.end(status: "error", fields: ["error": error.localizedDescription])
        }
    }

    func prefetchIfNeeded(campaignId: String) async {
        guard !Task.isCancelled else { return }
        await refreshState(campaignId: campaignId)
        guard NetworkMonitor.shared.isOnline else { return }
        if activeDownloads.contains(campaignId) { return }
        let existingState = if let cachedState = states[campaignId] {
            cachedState
        } else {
            await campaignRepository.getDownloadState(campaignId: campaignId)
        }

        if let existingState,
           existingState.isAvailableOffline, readiness[campaignId]?.isVerified == true {
            states[campaignId] = existingState
            return
        }

        await makeAvailableOffline(campaignId: campaignId)
    }

    func ensureAvailableOffline(
        campaignId: String,
        timeoutSeconds: TimeInterval = 300,
        pollIntervalSeconds: TimeInterval = 0.75
    ) async -> Bool {
        await prefetchIfNeeded(campaignId: campaignId)
        if !NetworkMonitor.shared.isOnline {
            await refreshState(campaignId: campaignId)
            return states[campaignId]?.isAvailableOffline == true &&
                readiness[campaignId]?.isVerified == true
        }
        return await waitUntilAvailableOffline(
            campaignId: campaignId,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds
        )
    }

    func waitUntilAvailableOffline(
        campaignId: String,
        timeoutSeconds: TimeInterval = 300,
        pollIntervalSeconds: TimeInterval = 0.75
    ) async -> Bool {
        let start = Date()
        let pollNanos = UInt64(max(0.25, pollIntervalSeconds) * 1_000_000_000)

        while Date().timeIntervalSince(start) < timeoutSeconds {
            await refreshState(campaignId: campaignId)

            if states[campaignId]?.status == "failed" {
                return false
            }

            if states[campaignId]?.isAvailableOffline == true,
               readiness[campaignId]?.isVerified == true {
                return true
            }

            try? await Task.sleep(nanoseconds: pollNanos)
        }

        await refreshState(campaignId: campaignId)
        return states[campaignId]?.isAvailableOffline == true &&
            readiness[campaignId]?.isVerified == true
    }

    func ensureMapAssetsAvailable(
        campaignId: String,
        timeoutSeconds: TimeInterval = 180,
        pollIntervalSeconds: TimeInterval = 0.5
    ) async -> Bool {
        OfflinePreloadCoordinator.shared.pauseForForegroundWork(reason: "ensure_map_assets", campaignId: campaignId)
        await refreshMapAssetReadiness(campaignId: campaignId)
        if mapAssetReadiness[campaignId]?.isMapReady == true {
            return true
        }

        guard NetworkMonitor.shared.isOnline else { return false }

        if !activeMapAssetDownloads.contains(campaignId) {
            let startedDownload = await makeMapAssetsAvailable(campaignId: campaignId)
            if !startedDownload {
                return mapAssetReadiness[campaignId]?.isMapReady == true
            }
        }

        return await waitUntilMapAssetsAvailable(
            campaignId: campaignId,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds
        )
    }

    func ensureUsableMapAssetsAvailable(
        campaignId: String,
        timeoutSeconds: TimeInterval = 45,
        pollIntervalSeconds: TimeInterval = 0.5
    ) async -> Bool {
        OfflinePreloadCoordinator.shared.pauseForForegroundWork(reason: "ensure_usable_map_assets", campaignId: campaignId)
        await refreshMapAssetReadiness(campaignId: campaignId)
        if mapAssetReadiness[campaignId]?.isMapUsable == true {
            return true
        }

        guard NetworkMonitor.shared.isOnline else { return false }

        if !activeMapAssetDownloads.contains(campaignId) {
            _ = await makeMapAssetsAvailable(campaignId: campaignId)
            if mapAssetReadiness[campaignId]?.isMapUsable == true {
                return true
            }
        }

        let start = Date()
        let pollNanos = UInt64(max(0.25, pollIntervalSeconds) * 1_000_000_000)
        while Date().timeIntervalSince(start) < timeoutSeconds {
            await refreshMapAssetReadiness(campaignId: campaignId)
            if mapAssetReadiness[campaignId]?.isMapUsable == true {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanos)
        }

        await refreshMapAssetReadiness(campaignId: campaignId)
        return mapAssetReadiness[campaignId]?.isMapUsable == true
    }

    func waitUntilMapAssetsAvailable(
        campaignId: String,
        timeoutSeconds: TimeInterval = 180,
        pollIntervalSeconds: TimeInterval = 0.5
    ) async -> Bool {
        let start = Date()
        let pollNanos = UInt64(max(0.25, pollIntervalSeconds) * 1_000_000_000)

        while Date().timeIntervalSince(start) < timeoutSeconds {
            await refreshMapAssetReadiness(campaignId: campaignId)
            if mapAssetReadiness[campaignId]?.isMapReady == true {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanos)
        }

        await refreshMapAssetReadiness(campaignId: campaignId)
        return mapAssetReadiness[campaignId]?.isMapReady == true
    }

    private func makeMapAssetsAvailable(campaignId: String) async -> Bool {
        OfflinePreloadCoordinator.shared.pauseForForegroundWork(reason: "make_map_assets_available", campaignId: campaignId)
        guard let campaignUUID = UUID(uuidString: campaignId) else { return false }
        guard !activeMapAssetDownloads.contains(campaignId) else { return true }

        activeMapAssetDownloads.insert(campaignId)
        defer { activeMapAssetDownloads.remove(campaignId) }

        mapAssetReadiness[campaignId] = CampaignMapAssetReadiness(
            campaignId: campaignId,
            isMapReady: false,
            missingComponents: ["map bundle", "buildings", "addresses"],
            buildingsCount: 0,
            addressesCount: 0,
            linksCount: 0,
            roadsCount: 0,
            hasLinkedAddressIdentity: false,
            progressPercent: 5
        )

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

            _ = try await fetchAndPersistCampaignMapBundle(campaignId: campaignId)
            await updateMapAssetProgress(campaignId: campaignId, progressPercent: 100)

            await refreshMapAssetReadiness(campaignId: campaignId)
            return true
        } catch {
            await refreshMapAssetReadiness(campaignId: campaignId)
            print("⚠️ [CampaignDownload] Map asset download failed for \(campaignId): \(error.localizedDescription)")
            return false
        }
    }

    private func updateMapAssetProgress(campaignId: String, progressPercent: Int) async {
        let current = await computeMapAssetReadiness(campaignId: campaignId)
        mapAssetReadiness[campaignId] = CampaignMapAssetReadiness(
            campaignId: campaignId,
            isMapReady: current.isMapReady,
            missingComponents: current.missingComponents,
            buildingsCount: current.buildingsCount,
            addressesCount: current.addressesCount,
            linksCount: current.linksCount,
            roadsCount: current.roadsCount,
            hasLinkedAddressIdentity: current.hasLinkedAddressIdentity,
            progressPercent: max(current.progressPercent, min(max(progressPercent, 0), 100))
        )
    }

    func computeMapAssetReadiness(campaignId: String) async -> CampaignMapAssetReadiness {
        let assetCounts = await campaignRepository.getOfflineAssetCounts(campaignId: campaignId)
        let bundleMetadata = await campaignRepository.getCampaignMapBundleMetadata(campaignId: campaignId)
        let hasCanonicalBundle = bundleMetadata != nil
        let buildingsCount = assetCounts.buildings
        let addressesCount = assetCounts.addresses
        let roadsCount = assetCounts.roads
        let hasLinkedAddressIdentity = assetCounts.buildingLinks > 0 || (bundleMetadata?.cachedLinkCount ?? 0) > 0

        var missing: [String] = []
        if !hasCanonicalBundle { missing.append("map bundle") }
        if buildingsCount == 0 { missing.append("buildings") }
        if addressesCount == 0 { missing.append("addresses") }

        let progressPercent: Int
        if missing.isEmpty {
            progressPercent = 100
        } else if buildingsCount > 0 || addressesCount > 0 {
            progressPercent = 65
        } else {
            progressPercent = 0
        }

        return CampaignMapAssetReadiness(
            campaignId: campaignId,
            isMapReady: missing.isEmpty,
            missingComponents: missing,
            buildingsCount: buildingsCount,
            addressesCount: addressesCount,
            linksCount: assetCounts.buildingLinks,
            roadsCount: roadsCount,
            hasLinkedAddressIdentity: hasLinkedAddressIdentity,
            progressPercent: progressPercent
        )
    }

    func makeAvailableOffline(campaignId: String) async {
        let trace = PerfTrace.begin("campaign_open", "make_available_offline", fields: [
            "campaign": campaignId
        ])
        guard let campaignUUID = UUID(uuidString: campaignId) else {
            trace.end(status: "invalid_campaign_id")
            return
        }
        guard !activeDownloads.contains(campaignId) else {
            await refreshState(campaignId: campaignId)
            trace.end(status: "already_downloading")
            return
        }

        let previousState = await campaignRepository.getDownloadState(campaignId: campaignId)
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
            try Task.checkCancellation()
            let metadataTrace = PerfTrace.begin("campaign_open", "offline_fetch_campaign_metadata", fields: ["campaign": campaignId])
            let metadata = try await fetchCampaignMetadata(campaignId: campaignUUID)
            metadataTrace.end(status: "success", fields: ["hasBoundary": metadata.boundaryGeoJSON != nil])
            try Task.checkCancellation()
            await campaignRepository.upsertCampaign(
                id: campaignId,
                name: metadata.name,
                mode: metadata.mode,
                boundaryGeoJSON: metadata.boundaryGeoJSON,
                payloadJSON: metadata.payloadJSON,
                downloadedAt: nil
            )

            let bundleTrace = PerfTrace.begin("campaign_open", "offline_fetch_map_bundle", fields: ["campaign": campaignId])
            let mapBundle = try await fetchAndPersistCampaignMapBundle(campaignId: campaignId)
            bundleTrace.end(status: "success", fields: [
                "buildings": mapBundle.buildings.features.count,
                "addresses": mapBundle.addresses.features.count,
                "parcels": mapBundle.parcels.features.count,
                "roads": mapBundle.roads.features.count,
                "links": mapBundle.links.count
            ])
            try Task.checkCancellation()
            await campaignRepository.updateDownloadState(campaignId: campaignId, status: "downloading", progress: 0.50, startedAt: startedAt)
            setTransientState(campaignId: campaignId, status: "downloading", progress: 0.50, startedAt: startedAt, errorMessage: nil)

            let orphansTrace = PerfTrace.begin("campaign_open", "offline_fetch_address_orphans", fields: ["campaign": campaignId])
            let addressOrphans = try await fetchAddressOrphans(campaignId: campaignUUID)
            orphansTrace.end(status: "success", fields: ["orphans": addressOrphans.count])
            try Task.checkCancellation()
            await campaignRepository.upsertAddressOrphans(campaignId: campaignId, orphans: addressOrphans)
            await campaignRepository.updateDownloadState(campaignId: campaignId, status: "downloading", progress: 0.55, startedAt: startedAt)
            setTransientState(campaignId: campaignId, status: "downloading", progress: 0.55, startedAt: startedAt, errorMessage: nil)

            let addressMetadataTrace = PerfTrace.begin("campaign_open", "offline_fetch_address_metadata", fields: ["campaign": campaignId])
            let addressMetadata = try await fetchCampaignAddressMetadata(campaignId: campaignUUID)
            addressMetadataTrace.end(status: "success", fields: ["rows": addressMetadata.count])
            try Task.checkCancellation()
            await campaignRepository.upsertAddressCaptureMetadata(
                campaignId: campaignUUID,
                responses: addressMetadata,
                dirty: false
            )

            let statusesTrace = PerfTrace.begin("campaign_open", "offline_fetch_statuses", fields: ["campaign": campaignId])
            let statuses = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignUUID, forceRefresh: true)
            statusesTrace.end(status: "success", fields: ["statuses": statuses.count])
            try Task.checkCancellation()
            await campaignRepository.upsertStatuses(rows: Array(statuses.values))
            await campaignRepository.updateDownloadState(campaignId: campaignId, status: "downloading", progress: 0.80, startedAt: startedAt)
            setTransientState(campaignId: campaignId, status: "downloading", progress: 0.80, startedAt: startedAt, errorMessage: nil)

            let contactsTrace = PerfTrace.begin("campaign_open", "offline_fetch_contacts", fields: ["campaign": campaignId])
            let contacts = try await fetchCampaignContacts(campaignId: campaignUUID)
            contactsTrace.end(status: "success", fields: ["contacts": contacts.count])
            try Task.checkCancellation()
            await ContactRepository.shared.upsertContacts(contacts, userId: nil, workspaceId: nil, dirty: false, syncedAt: Date())

            let activitiesTrace = PerfTrace.begin("campaign_open", "offline_fetch_contact_activities", fields: [
                "campaign": campaignId,
                "contacts": contacts.count
            ])
            let contactActivities = try await fetchCampaignContactActivities(contactIds: contacts.map(\.id))
            activitiesTrace.end(status: "success", fields: ["activities": contactActivities.count])
            try Task.checkCancellation()
            await ContactRepository.shared.upsertActivities(contactActivities, dirty: false, syncedAt: Date())

            setTransientState(
                campaignId: campaignId,
                status: "downloading",
                progress: 0.82,
                startedAt: startedAt,
                errorMessage: nil
            )

            let tilesTrace = PerfTrace.begin("campaign_open", "offline_download_mapbox_region", fields: [
                "campaign": campaignId,
                "addresses": mapBundle.addresses.features.count
            ])
            try await MapboxOfflineService.shared.downloadCampaignRegion(
                campaignId: campaignId,
                boundaryGeoJSON: metadata.boundaryGeoJSON,
                addresses: mapBundle.addresses.features,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeDownloads.contains(campaignId),
                              self.states[campaignId]?.status == "downloading",
                              self.states[campaignId]?.startedAt == startedAt else { return }
                        self.setTransientState(
                            campaignId: campaignId,
                            status: "downloading",
                            progress: min(max(0.82 + (progress * 0.18), 0.82), 0.99),
                            startedAt: startedAt,
                            errorMessage: nil
                        )
                    }
                }
            )
            tilesTrace.end(status: "success")
            try Task.checkCancellation()

            let readiness = await computeReadiness(
                campaignId: campaignId,
                expected: OfflineExpectedCounts(
                    buildings: mapBundle.buildings.features.count,
                    addresses: mapBundle.addresses.features.count,
                    buildingLinks: mapBundle.links.count,
                    statuses: statuses.count,
                    roads: mapBundle.roads.features.count,
                    metadata: addressMetadata.count,
                    contacts: contacts.count,
                    activities: contactActivities.count
                ),
                mapTilesReady: await MapboxOfflineService.shared.hasCompleteCampaignRegion(campaignId: campaignId)
            )
            self.readiness[campaignId] = readiness
            guard readiness.isVerified else {
                trace.end(status: "verification_failed", fields: [
                    "missing": readiness.missingComponents.joined(separator: ",")
                ])
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
            trace.end(status: "ready", fields: [
                "buildings": readiness.buildingsCount,
                "addresses": readiness.addressesCount,
                "contacts": readiness.contactsCount,
                "activities": readiness.activitiesCount,
                "statuses": readiness.statusesCount,
                "roads": readiness.roadsCount
            ])
        } catch {
            if Task.isCancelled || Self.isCancellation(error) {
                trace.end(status: "cancelled")
                await restoreDownloadStateAfterCancellation(campaignId: campaignId, previousState: previousState)
                await refreshState(campaignId: campaignId)
                return
            }
            trace.end(status: "error", fields: [
                "error": error.localizedDescription
            ])
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

    private func restoreDownloadStateAfterCancellation(campaignId: String, previousState: CampaignDownloadState?) async {
        if let previousState {
            await campaignRepository.updateDownloadState(
                campaignId: campaignId,
                status: previousState.status,
                progress: previousState.progress,
                startedAt: previousState.startedAt,
                completedAt: previousState.completedAt,
                errorMessage: previousState.errorMessage,
                lastSyncedAt: previousState.lastSyncedAt
            )
        } else {
            await campaignRepository.updateDownloadState(
                campaignId: campaignId,
                status: "not_downloaded",
                progress: 0,
                errorMessage: nil
            )
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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

    private func fetchAndPersistCampaignMapBundle(campaignId: String) async throws -> CanonicalCampaignMapBundle {
        let compactUserId = AuthManager.shared.user?.id
        let compactWorkspaceId = WorkspaceContext.shared.workspaceId
        let result = try await BuildingLinkService.shared.fetchCanonicalCampaignMapBundle(
            campaignId: campaignId,
            localSignature: nil
        )

        guard case .bundle(let bundle) = result else {
            throw CampaignOfflineVerificationError.mapBundleUnavailable
        }

        // A package is not advertised as offline-ready until all tile bytes have
        // passed checksum verification. Keep the previous canonical cache on failure.
        if let tiles = bundle.tiles {
            let archiveTrace = PerfTrace.begin("campaign_open", "offline_archive", fields: ["campaign": campaignId])
            _ = try await CanonicalTilePackageStore.shared.download(tiles)
            archiveTrace.end(status: "ready")
            if tiles.geometryPack != nil { _ = try await CanonicalTilePackageStore.shared.downloadExactGeometry(tiles) }

            // V3 is already prepared by the primary loader. Only older tile
            // responses need this compatibility preparation.
            if bundle.storageFormat != "tiles-v3", let compactUserId {
                do {
                    if let (data, compact) = try await BuildingLinkService.shared.fetchCompactCampaignMapBundle(campaignId: campaignId) {
                        guard compact.canonicalSignature == bundle.canonicalSignature,
                              compact.tiles.geometryRevision == tiles.geometryRevision,
                              compact.tiles.sha256 == tiles.sha256,
                              compact.tiles.geometryPack?.sha256 == tiles.geometryPack?.sha256,
                              AuthManager.shared.user?.id == compactUserId,
                              WorkspaceContext.shared.workspaceId == compactWorkspaceId,
                              !Task.isCancelled else { throw CampaignOfflineVerificationError.mapBundleUnavailable }
                        let geometryURL = try await CanonicalTilePackageStore.shared.downloadExactGeometry(compact.tiles)
                        guard AuthManager.shared.user?.id == compactUserId,
                              WorkspaceContext.shared.workspaceId == compactWorkspaceId,
                              !Task.isCancelled else { throw CancellationError() }
                        _ = try await CanonicalCompactCampaignStore.shared.save(data: data, campaignId: campaignId,
                            userId: compactUserId.uuidString, workspaceId: compactWorkspaceId?.uuidString,
                            geometryURL: geometryURL)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if Task.isCancelled || Self.isCancellation(error) { throw error }
                    // The existing offline bundle remains usable until compact
                    // field data is connected to all campaign operations.
                    print("⚠️ [MAP_DEBUG] compact_offline_prepare_failed campaign=\(campaignId) error=\(error.localizedDescription)")
                }
            }
        }

        if let compactUserId {
            guard AuthManager.shared.user?.id == compactUserId,
                  WorkspaceContext.shared.workspaceId == compactWorkspaceId,
                  !Task.isCancelled else { throw CancellationError() }
        }

        let persistTrace = PerfTrace.begin("campaign_open", "offline_persist_records", fields: ["campaign": campaignId])
        let persisted = await campaignRepository.replaceCampaignMapBundle(
            campaignId: campaignId,
            bundle: bundle
        )
        persistTrace.end(status: persisted ? "ready" : "error")
        guard persisted else {
            throw CampaignOfflineVerificationError.mapBundlePersistFailed
        }

        print(
            "🧪 [MAP_DEBUG] offline_map_bundle_persisted campaign=\(campaignId) " +
            "buildings=\(bundle.buildings.features.count) addresses=\(bundle.addresses.features.count) " +
            "parcels=\(bundle.parcels.features.count) roads=\(bundle.roads.features.count) links=\(bundle.links.count)"
        )
        return bundle
    }

    private func fetchCampaignAddressMetadata(campaignId: UUID) async throws -> [CampaignAddressResponse] {
        do {
            return try await fetchCampaignAddressMetadataPages(campaignId: campaignId, pagesPerBatch: 2)
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw error }
            // Some database plans time out under parallel load. Retry the
            // complete, ordered read serially instead of failing the download.
            print("⚠️ [CampaignDownload] Parallel address fetch failed; retrying serially: \(error.localizedDescription)")
            return try await fetchCampaignAddressMetadataPages(campaignId: campaignId, pagesPerBatch: 1)
        }
    }

    private func fetchCampaignAddressMetadataPages(campaignId: UUID, pagesPerBatch: Int) async throws -> [CampaignAddressResponse] {
        var rows: [CampaignAddressResponse] = []
        var nextPage = 0

        while true {
            let pages = try await withThrowingTaskGroup(of: (Int, [CampaignAddressResponse]).self) { group in
                for pageIndex in nextPage..<(nextPage + pagesPerBatch) {
                    group.addTask {
                        (pageIndex, try await Self.fetchCampaignAddressMetadataPage(campaignId: campaignId, pageIndex: pageIndex))
                    }
                }
                var collected: [(Int, [CampaignAddressResponse])] = []
                for try await page in group { collected.append(page) }
                return collected.sorted { $0.0 < $1.0 }
            }
            for (_, page) in pages {
                rows.append(contentsOf: page)
                if page.count < Self.pageSize { return rows }
            }
            nextPage += pagesPerBatch
        }
    }

    private static func fetchCampaignAddressMetadataPage(campaignId: UUID, pageIndex: Int) async throws -> [CampaignAddressResponse] {
            let from = pageIndex * pageSize
            let to = from + pageSize - 1
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
                .order("created_at", ascending: true)
                .order("id", ascending: true)
                .range(from: from, to: to)
                .execute()
            return try JSONDecoder.supabaseDates.decode([CampaignAddressResponse].self, from: response.data)
    }

    private func fetchAddressOrphans(campaignId: UUID) async throws -> [CampaignAddressOrphanSnapshot] {
        let response = try await SupabaseManager.shared.client
            .from("address_orphans")
            .select("address_id, coordinate, status, nearest_building_id, nearest_distance, suggested_street, address_street")
            .eq("campaign_id", value: campaignId.uuidString)
            .in("status", values: ["pending", "pending_review", "ambiguous_match"])
            .execute()

        let object = try JSONSerialization.jsonObject(with: response.data)
        guard let rows = object as? [[String: Any]] else { return [] }

        return rows.compactMap { row in
            guard let addressId = row["address_id"] as? String,
                  !addressId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            return CampaignAddressOrphanSnapshot(
                addressId: addressId,
                nearestBuildingId: row["nearest_building_id"] as? String,
                nearestDistance: Self.doubleValue(row["nearest_distance"]),
                status: row["status"] as? String,
                suggestedStreet: row["suggested_street"] as? String,
                addressStreet: row["address_street"] as? String,
                coordinateJSON: Self.jsonString(row["coordinate"])
            )
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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
        let mapMetadata = await campaignRepository.getCampaignMapBundleMetadata(campaignId: campaignId)
        let contactCounts = await ContactRepository.shared.getOfflineCounts(campaignId: UUID(uuidString: campaignId) ?? UUID())
        let baseMapTilesReady: Bool
        if let mapTilesReady {
            baseMapTilesReady = mapTilesReady
        } else {
            // The published status can lag behind a finished download. Verify
            // the actual region instead of inferring its presence from status.
            baseMapTilesReady = await MapboxOfflineService.shared.hasCompleteCampaignRegion(campaignId: campaignId)
        }

        let canonicalPackageReady: Bool
        if let tiles = mapMetadata?.canonicalTiles {
            canonicalPackageReady = await CanonicalTilePackageStore.shared.hasVerifiedPackage(tiles)
        } else {
            // V3 bundles must not be treated as legacy if their manifest is missing.
            canonicalPackageReady = mapMetadata?.usesCompactTiles != true
        }
        let resolvedMapTilesReady = baseMapTilesReady && canonicalPackageReady

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
        if mapMetadata == nil { missing.append("map bundle") }
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
            .select()
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

@MainActor
final class OfflinePreloadCoordinator: ObservableObject {
    static let shared = OfflinePreloadCoordinator()

    @Published private(set) var isPreloading = false
    @Published private(set) var lastPreloadAt: Date?
    @Published private(set) var lastSelectedCount = 0
    @Published private(set) var lastStorageBytes: Int64 = 0

    private let campaignDownloadService = CampaignDownloadService.shared
    private let campaignRepository = CampaignRepository.shared
    private let sessionStartCacheRepository = SessionStartCacheRepository.shared
    private let networkMonitor = NetworkMonitor.shared
    private var preloadTask: Task<Void, Never>?
    private var pausedUntil: Date?
    private var foregroundMapTokens = Set<UUID>()
    private var requiredDownloadTask: Task<Void, Never>?
    private var connectivitySubscription: AnyCancellable?

    // Scope durable download requests to the signed-in user and workspace.
    private var requiredDownloadKey: String? {
        guard let userId = AuthManager.shared.user?.id else { return nil }
        return "required_campaign_downloads.\(userId.uuidString).\(WorkspaceContext.shared.workspaceId?.uuidString ?? "personal")"
    }

    private var requiredCampaignIds: Set<String> {
        guard let key = requiredDownloadKey else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private func storeRequiredCampaignIds(_ ids: Set<String>, key: String) {
        UserDefaults.standard.set(ids.sorted(), forKey: key)
    }

    private init() {
        connectivitySubscription = networkMonitor.$isOnline
            .combineLatest(AuthManager.shared.$user, WorkspaceContext.shared.$workspaceId)
            .sink { [weak self] online, user, _ in
                guard online, user != nil else { return }
                Task { @MainActor [weak self] in
                    self?.scheduleRequiredDownloads()
                }
            }
    }

    /// Event-driven downloads are independent of the optional recent-campaign limit.
    func requireLocalCampaigns(_ campaignIds: [UUID], refreshExisting: Bool = false) {
        guard let key = requiredDownloadKey, !campaignIds.isEmpty else { return }
        let ids = Set(campaignIds.map(\.uuidString))
        let retained = Set(UserDefaults.standard.stringArray(forKey: key + ".retained") ?? [])
        storeRequiredCampaignIds(retained.union(ids), key: key + ".retained")
        if refreshExisting {
            let refresh = Set(UserDefaults.standard.stringArray(forKey: key + ".refresh") ?? [])
            storeRequiredCampaignIds(refresh.union(ids), key: key + ".refresh")
        }
        storeRequiredCampaignIds(requiredCampaignIds.union(ids), key: key)
        scheduleRequiredDownloads()
    }

    private func scheduleRequiredDownloads() {
        guard OfflineFirstConfig.isEnabled, networkMonitor.isOnline,
              requiredDownloadTask == nil, !requiredCampaignIds.isEmpty else { return }
        requiredDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.requiredDownloadTask = nil }
            while !Task.isCancelled, self.networkMonitor.isOnline,
                  let key = self.requiredDownloadKey, !self.requiredCampaignIds.isEmpty {
                if !self.isPausedForForegroundWork {
                    for id in self.requiredCampaignIds.sorted() {
                        guard !Task.isCancelled, self.networkMonitor.isOnline,
                              self.requiredDownloadKey == key else { break }
                        guard let campaignId = UUID(uuidString: id) else { continue }
                        do {
                            // Creation returns a shell; do not cache it as a finished campaign.
                            let state = try await CampaignsAPI.shared.fetchProvisionState(campaignId: campaignId)
                            guard self.requiredDownloadKey == key else { break }
                            let legacyReady = state.provisionStatus == nil && state.provisionPhase == nil
                            guard state.provisionStatus == .ready || legacyReady else { continue }
                            let refresh = Set(UserDefaults.standard.stringArray(forKey: key + ".refresh") ?? [])
                            if refresh.contains(id) {
                                await self.campaignDownloadService.makeAvailableOffline(campaignId: id)
                            } else {
                                await self.campaignDownloadService.prefetchIfNeeded(campaignId: id)
                            }
                            guard self.requiredDownloadKey == key else { break }
                            if self.campaignDownloadService.states[id]?.isAvailableOffline == true,
                               self.campaignDownloadService.readiness(for: id)?.isVerified == true {
                                var pending = self.requiredCampaignIds
                                pending.remove(id)
                                self.storeRequiredCampaignIds(pending, key: key)
                                let remainingRefresh = Set(UserDefaults.standard.stringArray(forKey: key + ".refresh") ?? [])
                                self.storeRequiredCampaignIds(remainingRefresh.subtracting([id]), key: key + ".refresh")
                            }
                        } catch {
                            // Preserve the request for reconnect/relaunch and transient failures.
                            print("⚠️ [OfflinePreload] Required campaign download deferred: \(error.localizedDescription)")
                        }
                    }
                }
                guard !self.requiredCampaignIds.isEmpty else { break }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func schedule(reason: String) {
        scheduleRequiredDownloads()
        guard OfflineFirstConfig.isEnabled else { return }
        guard networkMonitor.isOnline else { return }
        if networkMonitor.isCellular && !OfflineFirstConfig.cellularPreloadAllowed { return }
        if isPausedForForegroundWork {
            scheduleAfterPause(reason: reason)
            return
        }
        guard preloadTask == nil else { return }

        preloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(reason: reason)
            self.preloadTask = nil
        }
    }

    func beginForegroundMap(_ token: UUID) {
        guard foregroundMapTokens.insert(token).inserted else { return }
        preloadTask?.cancel()
        preloadTask = nil
    }

    func endForegroundMap(_ token: UUID) {
        foregroundMapTokens.remove(token)
        if foregroundMapTokens.isEmpty { schedule(reason: "map_closed") }
    }

    func pauseForForegroundWork(
        reason: String,
        campaignId: String? = nil,
        resumeDelaySeconds: TimeInterval = 30
    ) {
        let resumeAt = Date().addingTimeInterval(max(1, resumeDelaySeconds))
        if let pausedUntil, pausedUntil > resumeAt {
            return
        }
        pausedUntil = resumeAt
        if let preloadTask {
            preloadTask.cancel()
            self.preloadTask = nil
            PerfTrace.event("offline_first", "preload.cancelled_for_foreground", fields: [
                "reason": reason,
                "campaign": campaignId ?? ""
            ])
        }
        scheduleAfterPause(reason: "resume_after_\(reason)")
    }

    func run(reason: String) async {
        guard OfflineFirstConfig.isEnabled else { return }
        guard networkMonitor.isOnline else { return }
        if networkMonitor.isCellular && !OfflineFirstConfig.cellularPreloadAllowed { return }
        if isPausedForForegroundWork {
            scheduleAfterPause(reason: reason)
            return
        }
        guard !isPreloading else { return }

        isPreloading = true
        let trace = PerfTrace.begin("offline_first", "preload", fields: [
            "reason": reason,
            "cellular": networkMonitor.isCellular,
            "capGB": OfflineFirstConfig.offlineStorageCapGB
        ])
        defer { isPreloading = false }

        let candidates = await selectCandidates()
        lastSelectedCount = candidates.count
        let preloadCandidates = Array(candidates.prefix(OfflineFirstConfig.maxBackgroundPreloadCampaigns))
        for candidate in preloadCandidates {
            guard !Task.isCancelled else { break }
            guard !isPausedForForegroundWork else { break }
            guard networkMonitor.isOnline else { break }
            if networkMonitor.isCellular && !OfflineFirstConfig.cellularPreloadAllowed { break }
            await campaignDownloadService.prefetchIfNeeded(campaignId: candidate.campaignId.uuidString)
        }

        let retainedIds = requiredDownloadKey.map {
            UserDefaults.standard.stringArray(forKey: $0 + ".retained") ?? []
        } ?? []
        let protectedIds = Set(preloadCandidates.map(\.campaignId))
            .union(retainedIds.compactMap { UUID(uuidString: $0) })
        await enforceStorageCap(protectedCampaignIds: protectedIds)
        lastPreloadAt = Date()
        trace.end(status: "done", fields: [
            "selected": candidates.count,
            "processed": preloadCandidates.count,
            "storageBytes": lastStorageBytes
        ])
    }

    private var isPausedForForegroundWork: Bool {
        if !foregroundMapTokens.isEmpty { return true }
        guard let pausedUntil else { return false }
        if pausedUntil <= Date() {
            self.pausedUntil = nil
            return false
        }
        return true
    }

    private func scheduleAfterPause(reason: String) {
        guard foregroundMapTokens.isEmpty, preloadTask == nil else { return }
        let delaySeconds = max(1, pausedUntil?.timeIntervalSinceNow ?? 1)
        preloadTask = Task { @MainActor [weak self] in
            let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.preloadTask = nil
            await self.run(reason: reason)
        }
    }

    private func selectCandidates() async -> [OfflinePreloadCandidate] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -OfflineFirstConfig.activeCampaignWindowDays,
            to: Date()
        ) ?? Date().addingTimeInterval(TimeInterval(-OfflineFirstConfig.activeCampaignWindowDays * 86_400))
        let recentCampaignIds = await campaignRepository.getRecentlyUpdatedCampaignIds(since: cutoff)

        var assignedCampaignIds: [UUID] = []
        if let workspaceId = WorkspaceContext.shared.workspaceId {
            assignedCampaignIds = await sessionStartCacheRepository
                .getCachedRouteAssignments(workspaceId: workspaceId)
                .compactMap(\.campaignId)
        }

        var farmCampaignIds: [UUID] = []
        if let userId = AuthManager.shared.user?.id {
            let farms = await sessionStartCacheRepository.getCachedFarms(
                userId: userId,
                workspaceId: WorkspaceContext.shared.workspaceId
            )
            for farm in farms where farm.isActive {
                let touches = await FarmOfflineRepository.shared.getCachedTouches(farmId: farm.id)
                farmCampaignIds.append(contentsOf: touches.filter { !$0.completed }.compactMap(\.campaignId))
            }
        }

        return OfflinePreloadSelector.selectCandidates(
            assignedCampaignIds: assignedCampaignIds,
            recentCampaignIds: recentCampaignIds,
            inProgressFarmCampaignIds: farmCampaignIds
        )
    }

    private func enforceStorageCap(protectedCampaignIds: Set<UUID>) async {
        var storageBytes = await campaignRepository.estimatedOfflineStorageBytes()
        lastStorageBytes = storageBytes
        guard storageBytes > OfflineFirstConfig.offlineStorageCapBytes else { return }

        let candidates = await campaignRepository.offlineCampaignEvictionCandidates(excluding: protectedCampaignIds)
        var evicted = 0
        for campaignId in candidates {
            guard storageBytes > OfflineFirstConfig.offlineStorageCapBytes else { break }
            await campaignRepository.evictOfflineAssets(campaignId: campaignId)
            evicted += 1
            storageBytes = await campaignRepository.estimatedOfflineStorageBytes()
            lastStorageBytes = storageBytes
        }

        PerfTrace.event("offline_first", "storage_eviction", fields: [
            "evicted": evicted,
            "storageBytes": storageBytes,
            "capBytes": OfflineFirstConfig.offlineStorageCapBytes
        ])
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
    case mapBundleUnavailable
    case mapBundlePersistFailed
    case verificationFailed([String])

    var errorDescription: String? {
        switch self {
        case .mapBundleUnavailable:
            return "Campaign map bundle could not be downloaded."
        case .mapBundlePersistFailed:
            return "Campaign map bundle could not be saved on this device."
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
