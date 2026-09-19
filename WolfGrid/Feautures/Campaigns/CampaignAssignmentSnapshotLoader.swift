import Foundation

struct CampaignAssignmentSnapshot {
    let routeAssignments: [RouteAssignmentSummary]
    let campaignAssignments: [CampaignAssignmentSummary]

    static let empty = CampaignAssignmentSnapshot(routeAssignments: [], campaignAssignments: [])

    var campaignListAssignedIDs: Set<UUID> {
        let routeIDs = routeAssignments
            .filter(Self.isActiveForCampaignList)
            .compactMap(\.campaignId)
        let directIDs = campaignAssignments
            .filter(\.isActive)
            .map(\.campaignId)
        return Set(routeIDs).union(directIDs)
    }

    var activeRouteAssignmentsForPresentation: [RouteAssignmentSummary] {
        routeAssignments.filter(Self.isActiveForPresentation)
    }

    var activeCampaignAssignments: [CampaignAssignmentSummary] {
        campaignAssignments.filter(\.isActive)
    }

    private static func isActiveForCampaignList(_ assignment: RouteAssignmentSummary) -> Bool {
        !["completed", "complete", "cancelled", "canceled", "archived", "declined"]
            .contains(normalizedStatus(assignment.status))
    }

    private static func isActiveForPresentation(_ assignment: RouteAssignmentSummary) -> Bool {
        !["completed", "cancelled", "canceled", "declined"]
            .contains(normalizedStatus(assignment.status))
    }

    private static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct CampaignListLoadResult {
    let campaigns: Result<[CampaignV2], Error>
    let assignmentSnapshot: CampaignAssignmentSnapshot
}

@MainActor
struct CampaignAssignmentSnapshotLoader {
    typealias RouteFetch = @MainActor (UUID) async throws -> [RouteAssignmentSummary]
    typealias RouteCacheWrite = @MainActor ([RouteAssignmentSummary], UUID) async -> Void
    typealias RouteCacheRead = @MainActor (UUID) async -> [RouteAssignmentSummary]
    typealias CampaignFetch = @MainActor (UUID) async throws -> [CampaignAssignmentSummary]

    private let fetchRouteAssignments: RouteFetch
    private let fetchLegacyRouteAssignments: RouteFetch
    private let cacheRouteAssignments: RouteCacheWrite
    private let readCachedRouteAssignments: RouteCacheRead
    private let fetchCampaignAssignments: CampaignFetch

    init(
        fetchRouteAssignments: @escaping RouteFetch,
        fetchLegacyRouteAssignments: @escaping RouteFetch,
        cacheRouteAssignments: @escaping RouteCacheWrite,
        readCachedRouteAssignments: @escaping RouteCacheRead,
        fetchCampaignAssignments: @escaping CampaignFetch
    ) {
        self.fetchRouteAssignments = fetchRouteAssignments
        self.fetchLegacyRouteAssignments = fetchLegacyRouteAssignments
        self.cacheRouteAssignments = cacheRouteAssignments
        self.readCachedRouteAssignments = readCachedRouteAssignments
        self.fetchCampaignAssignments = fetchCampaignAssignments
    }

    func load(workspaceId: UUID) async -> CampaignAssignmentSnapshot {
        async let routeAssignments = loadRouteAssignments(workspaceId: workspaceId)
        async let campaignAssignments = loadCampaignAssignments(workspaceId: workspaceId)
        return await CampaignAssignmentSnapshot(
            routeAssignments: routeAssignments,
            campaignAssignments: campaignAssignments
        )
    }

    func loadCached(workspaceId: UUID) async -> CampaignAssignmentSnapshot {
        CampaignAssignmentSnapshot(
            routeAssignments: await readCachedRouteAssignments(workspaceId),
            campaignAssignments: []
        )
    }

    private func loadRouteAssignments(workspaceId: UUID) async -> [RouteAssignmentSummary] {
        do {
            let assignments = try await fetchRouteAssignments(workspaceId)
            await cacheRouteAssignments(assignments, workspaceId)
            return assignments
        } catch {
            print("⚠️ [Campaigns] Failed to load assigned route campaigns: \(error.localizedDescription)")
        }

        do {
            let assignments = try await fetchLegacyRouteAssignments(workspaceId)
            await cacheRouteAssignments(assignments, workspaceId)
            return assignments
        } catch {
            return await readCachedRouteAssignments(workspaceId)
        }
    }

    private func loadCampaignAssignments(workspaceId: UUID) async -> [CampaignAssignmentSummary] {
        do {
            return try await fetchCampaignAssignments(workspaceId)
        } catch {
            print("⚠️ [Campaigns] Failed to load campaign assignments: \(error.localizedDescription)")
            return []
        }
    }
}

extension CampaignAssignmentSnapshotLoader {
    static let live = CampaignAssignmentSnapshotLoader(
        fetchRouteAssignments: { workspaceId in
            try await RouteAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceId).assignments
        },
        fetchLegacyRouteAssignments: { workspaceId in
            try await RoutePlansAPI.shared.fetchMyAssignedRoutes(workspaceId: workspaceId)
        },
        cacheRouteAssignments: { assignments, workspaceId in
            let activeAssignments = CampaignAssignmentSnapshot(
                routeAssignments: assignments,
                campaignAssignments: []
            ).activeRouteAssignmentsForPresentation
            await SessionStartCacheRepository.shared.upsertRouteAssignments(
                activeAssignments,
                workspaceId: workspaceId
            )
        },
        readCachedRouteAssignments: { workspaceId in
            await SessionStartCacheRepository.shared.getCachedRouteAssignments(workspaceId: workspaceId)
        },
        fetchCampaignAssignments: { workspaceId in
            try await CampaignAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceId).assignments
        }
    )
}
