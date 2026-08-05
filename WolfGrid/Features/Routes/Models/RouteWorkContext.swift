import Foundation

struct RouteWorkContext: Equatable, Sendable {
    let assignmentId: UUID
    let routePlanId: UUID
    let campaignId: UUID
    let routeName: String
    let stops: [RoutePlanStop]

    init(
        assignmentId: UUID,
        routePlanId: UUID,
        campaignId: UUID,
        routeName: String,
        stops: [RoutePlanStop]
    ) {
        self.assignmentId = assignmentId
        self.routePlanId = routePlanId
        self.campaignId = campaignId
        self.routeName = routeName
        self.stops = stops.sorted { $0.stopOrder < $1.stopOrder }
    }

    init?(detail: RouteAssignmentDetailPayload) {
        guard let campaignId = detail.campaignId, !detail.stops.isEmpty else {
            return nil
        }

        self.init(
            assignmentId: detail.assignmentId,
            routePlanId: detail.routePlanId,
            campaignId: campaignId,
            routeName: detail.displayPlanName,
            stops: detail.stops
        )
    }

    init?(assignment: RouteAssignmentSummary, planDetail: RoutePlanDetail) {
        guard let campaignId = planDetail.campaignId, !planDetail.stops.isEmpty else {
            return nil
        }

        self.init(
            assignmentId: assignment.id,
            routePlanId: assignment.routePlanId,
            campaignId: campaignId,
            routeName: RouteAssignmentSummary.displayName(fromRoutePlanName: planDetail.name),
            stops: planDetail.stops
        )
    }

    var stopCount: Int {
        stops.count
    }

    var normalizedAddressIdSet: Set<String> {
        Set(stops.compactMap(\.addressId).map { $0.uuidString.lowercased() })
    }

    var normalizedBuildingIdentifierSet: Set<String> {
        Set(
            stops.flatMap { stop in
                [
                    stop.gersId,
                    stop.buildingId?.uuidString
                ]
                .compactMap(Self.normalizedIdentifier)
            }
        )
    }

    var normalizedBuildingOnlyIdentifierSet: Set<String> {
        Set(
            stops
                .filter { $0.addressId == nil }
                .flatMap { stop in
                    [
                        stop.gersId,
                        stop.buildingId?.uuidString
                    ]
                    .compactMap(Self.normalizedIdentifier)
                }
        )
    }

    func stopOrder(addressId: UUID?, buildingIdentifiers: [String] = []) -> Int? {
        var bestOrder: Int?

        if let addressId {
            let normalizedAddressId = addressId.uuidString.lowercased()
            bestOrder = stops.first(where: { stop in
                stop.addressId?.uuidString.lowercased() == normalizedAddressId
            })?.stopOrder
        }

        if bestOrder != nil {
            return bestOrder
        }

        let normalizedCandidates = Set(buildingIdentifiers.compactMap(Self.normalizedIdentifier))
        guard !normalizedCandidates.isEmpty else {
            return nil
        }

        for stop in stops {
            let stopCandidates = Set(
                [
                    stop.gersId,
                    stop.buildingId?.uuidString
                ]
                .compactMap(Self.normalizedIdentifier)
            )

            if !stopCandidates.isDisjoint(with: normalizedCandidates) {
                return stop.stopOrder
            }
        }

        return nil
    }

    static func normalizedIdentifier(_ rawValue: String?) -> String? {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}
