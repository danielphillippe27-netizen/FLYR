import Foundation
import Testing
@testable import WolfGrid

@MainActor
struct CampaignAssignmentSnapshotLoaderTests {
    @Test func loadFetchesEachAssignmentCollectionOnceAndSharesActiveIDs() async throws {
        let routeCampaignID = UUID()
        let completedRouteCampaignID = UUID()
        let directCampaignID = UUID()
        let cancelledDirectCampaignID = UUID()
        let routes = [
            try makeRouteAssignment(campaignID: routeCampaignID, status: "assigned"),
            try makeRouteAssignment(campaignID: completedRouteCampaignID, status: "completed")
        ]
        let campaignAssignments = try makeCampaignAssignments([
            (directCampaignID, "accepted"),
            (cancelledDirectCampaignID, "cancelled")
        ])

        var routeFetchCount = 0
        var campaignFetchCount = 0
        var legacyFetchCount = 0
        var cacheReadCount = 0
        var cacheWriteCount = 0
        let loader = CampaignAssignmentSnapshotLoader(
            fetchRouteAssignments: { _ in
                routeFetchCount += 1
                return routes
            },
            fetchLegacyRouteAssignments: { _ in
                legacyFetchCount += 1
                return []
            },
            cacheRouteAssignments: { _, _ in cacheWriteCount += 1 },
            readCachedRouteAssignments: { _ in
                cacheReadCount += 1
                return []
            },
            fetchCampaignAssignments: { _ in
                campaignFetchCount += 1
                return campaignAssignments
            }
        )

        let snapshot = await loader.load(workspaceId: UUID())

        #expect(routeFetchCount == 1)
        #expect(campaignFetchCount == 1)
        #expect(legacyFetchCount == 0)
        #expect(cacheReadCount == 0)
        #expect(cacheWriteCount == 1)
        #expect(snapshot.campaignListAssignedIDs == Set([routeCampaignID, directCampaignID]))
        #expect(snapshot.activeRouteAssignmentsForPresentation.map(\.campaignId) == [routeCampaignID])
        #expect(snapshot.activeCampaignAssignments.map(\.campaignId) == [directCampaignID])
    }

    @Test func routeFailureUsesLegacyOnceAndCachesItsResult() async throws {
        let campaignID = UUID()
        let legacyRoutes = [try makeRouteAssignment(campaignID: campaignID, status: "assigned")]
        var routeFetchCount = 0
        var legacyFetchCount = 0
        var cachedAssignments: [RouteAssignmentSummary] = []
        let loader = CampaignAssignmentSnapshotLoader(
            fetchRouteAssignments: { _ in
                routeFetchCount += 1
                throw TestFailure.expected
            },
            fetchLegacyRouteAssignments: { _ in
                legacyFetchCount += 1
                return legacyRoutes
            },
            cacheRouteAssignments: { assignments, _ in cachedAssignments = assignments },
            readCachedRouteAssignments: { _ in [] },
            fetchCampaignAssignments: { _ in [] }
        )

        let snapshot = await loader.load(workspaceId: UUID())

        #expect(routeFetchCount == 1)
        #expect(legacyFetchCount == 1)
        #expect(cachedAssignments == legacyRoutes)
        #expect(snapshot.campaignListAssignedIDs == Set([campaignID]))
    }

    @Test func routeFailuresUseCachedAssignmentsWithoutRepeatingNetworkCalls() async throws {
        let campaignID = UUID()
        let cachedRoutes = [try makeRouteAssignment(campaignID: campaignID, status: "assigned")]
        var routeFetchCount = 0
        var legacyFetchCount = 0
        var cacheReadCount = 0
        let loader = CampaignAssignmentSnapshotLoader(
            fetchRouteAssignments: { _ in
                routeFetchCount += 1
                throw TestFailure.expected
            },
            fetchLegacyRouteAssignments: { _ in
                legacyFetchCount += 1
                throw TestFailure.expected
            },
            cacheRouteAssignments: { _, _ in },
            readCachedRouteAssignments: { _ in
                cacheReadCount += 1
                return cachedRoutes
            },
            fetchCampaignAssignments: { _ in [] }
        )

        let snapshot = await loader.load(workspaceId: UUID())

        #expect(routeFetchCount == 1)
        #expect(legacyFetchCount == 1)
        #expect(cacheReadCount == 1)
        #expect(snapshot.activeRouteAssignmentsForPresentation == cachedRoutes)
    }

    private enum TestFailure: Error {
        case expected
    }

    private func makeRouteAssignment(campaignID: UUID, status: String) throws -> RouteAssignmentSummary {
        try #require(RouteAssignmentSummary([
            "assignment_id": UUID().uuidString,
            "route_plan_id": UUID().uuidString,
            "campaign_id": campaignID.uuidString,
            "name": "Test route",
            "status": status
        ]))
    }

    private func makeCampaignAssignments(
        _ values: [(campaignID: UUID, status: String)]
    ) throws -> [CampaignAssignmentSummary] {
        let rows = values.map { value in
            [
                "id": UUID().uuidString,
                "campaign_id": value.campaignID.uuidString,
                "workspace_id": UUID().uuidString,
                "assigned_to_user_id": UUID().uuidString,
                "assigned_by_user_id": UUID().uuidString,
                "mode": "individual",
                "status": value.status
            ]
        }
        return try JSONDecoder().decode(
            [CampaignAssignmentSummary].self,
            from: JSONSerialization.data(withJSONObject: rows)
        )
    }
}
