import Foundation

enum OnboardingDemoRolePath: String, Codable {
    case soloOwner = "solo_owner"
    case teamOwner = "team_owner"
    case member

    var isOwnerPath: Bool {
        self == .soloOwner || self == .teamOwner
    }
}

enum OnboardingDemoAction: Hashable {
    case openStarterCampaign
    case openCampaigns
    case openRecord
    case openLeads
    case openLeaderboard
    case openRoutes
    case createStarterCampaign
    case createRealCampaign
    case none
}

struct OnboardingDemoState: Codable, Equatable {
    let workspaceId: UUID?
    let userId: UUID?
    let rolePath: OnboardingDemoRolePath
    let seededCampaignId: UUID?
    let dismissedAt: Date?
    let completedChecklistItems: [String]
    let hasAssignedWork: Bool
    let canSeed: Bool
    let seedSkippedReason: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case workspaceIdCamel = "workspaceId"
        case userId = "user_id"
        case userIdCamel = "userId"
        case rolePath = "role_path"
        case rolePathCamel = "rolePath"
        case seededCampaignId = "seeded_campaign_id"
        case seededCampaignIdCamel = "seededCampaignId"
        case dismissedAt = "dismissed_at"
        case dismissedAtCamel = "dismissedAt"
        case completedChecklistItems = "completed_checklist_items"
        case completedChecklistItemsCamel = "completedChecklistItems"
        case hasAssignedWork = "has_assigned_work"
        case hasAssignedWorkCamel = "hasAssignedWork"
        case canSeed = "can_seed"
        case canSeedCamel = "canSeed"
        case seedSkippedReason = "seed_skipped_reason"
        case seedSkippedReasonCamel = "seedSkippedReason"
    }

    init(
        workspaceId: UUID?,
        userId: UUID?,
        rolePath: OnboardingDemoRolePath,
        seededCampaignId: UUID?,
        dismissedAt: Date?,
        completedChecklistItems: [String],
        hasAssignedWork: Bool,
        canSeed: Bool,
        seedSkippedReason: String?
    ) {
        self.workspaceId = workspaceId
        self.userId = userId
        self.rolePath = rolePath
        self.seededCampaignId = seededCampaignId
        self.dismissedAt = dismissedAt
        self.completedChecklistItems = completedChecklistItems
        self.hasAssignedWork = hasAssignedWork
        self.canSeed = canSeed
        self.seedSkippedReason = seedSkippedReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceId = try container.decodeFlexibleUUID(primary: .workspaceId, fallback: .workspaceIdCamel)
        userId = try container.decodeFlexibleUUID(primary: .userId, fallback: .userIdCamel)
        rolePath = try container.decodeIfPresent(OnboardingDemoRolePath.self, forKey: .rolePath)
            ?? container.decodeIfPresent(OnboardingDemoRolePath.self, forKey: .rolePathCamel)
            ?? .member
        seededCampaignId = try container.decodeFlexibleUUID(primary: .seededCampaignId, fallback: .seededCampaignIdCamel)
        dismissedAt = try container.decodeFlexibleDate(primary: .dismissedAt, fallback: .dismissedAtCamel)
        completedChecklistItems = try container.decodeIfPresent([String].self, forKey: .completedChecklistItems)
            ?? container.decodeIfPresent([String].self, forKey: .completedChecklistItemsCamel)
            ?? []
        hasAssignedWork = try container.decodeIfPresent(Bool.self, forKey: .hasAssignedWork)
            ?? container.decodeIfPresent(Bool.self, forKey: .hasAssignedWorkCamel)
            ?? false
        canSeed = try container.decodeIfPresent(Bool.self, forKey: .canSeed)
            ?? container.decodeIfPresent(Bool.self, forKey: .canSeedCamel)
            ?? false
        seedSkippedReason = try container.decodeIfPresent(String.self, forKey: .seedSkippedReason)
            ?? container.decodeIfPresent(String.self, forKey: .seedSkippedReasonCamel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(workspaceId, forKey: .workspaceId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(rolePath, forKey: .rolePath)
        try container.encodeIfPresent(seededCampaignId, forKey: .seededCampaignId)
        try container.encodeIfPresent(dismissedAt, forKey: .dismissedAt)
        try container.encode(completedChecklistItems, forKey: .completedChecklistItems)
        try container.encode(hasAssignedWork, forKey: .hasAssignedWork)
        try container.encode(canSeed, forKey: .canSeed)
        try container.encodeIfPresent(seedSkippedReason, forKey: .seedSkippedReason)
    }

    var isDismissed: Bool {
        dismissedAt != nil
    }
}

struct OnboardingDemoSeedResponse: Decodable {
    let seeded: Bool
    let skipped: Bool
    let reason: String?
    let campaignId: UUID?
    let state: OnboardingDemoState

    enum CodingKeys: String, CodingKey {
        case seeded, skipped, reason, state
        case campaignId = "campaign_id"
        case campaignIdCamel = "campaignId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seeded = try container.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
        skipped = try container.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        campaignId = try container.decodeFlexibleUUID(primary: .campaignId, fallback: .campaignIdCamel)
        state = try container.decode(OnboardingDemoState.self, forKey: .state)
    }
}

struct OnboardingDemoChecklistItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: OnboardingDemoAction

    static func items(for state: OnboardingDemoState) -> [OnboardingDemoChecklistItem] {
        if state.seedSkippedReason == "workspace_has_campaigns", state.rolePath.isOwnerPath {
            return ownerItems(hasStarter: false, team: state.rolePath == .teamOwner)
        }

        switch state.rolePath {
        case .soloOwner:
            return ownerItems(hasStarter: state.seededCampaignId != nil, team: false)
        case .teamOwner:
            return ownerItems(hasStarter: state.seededCampaignId != nil, team: true)
        case .member:
            return memberItems(hasAssignedWork: state.hasAssignedWork)
        }
    }

    private static func ownerItems(hasStarter: Bool, team: Bool) -> [OnboardingDemoChecklistItem] {
        var items: [OnboardingDemoChecklistItem] = []
        if hasStarter {
            items.append(.init(
                id: "open_starter_campaign",
                title: "Open Sugar House Starter Farm",
                subtitle: "Explore real homes, map colors, and campaign progress.",
                systemImage: "map.fill",
                action: .openStarterCampaign
            ))
        } else {
            items.append(.init(
                id: "create_starter_campaign",
                title: "Create starter campaign",
                subtitle: "Seed the editable Sugar House demo into this workspace.",
                systemImage: "sparkles",
                action: .createStarterCampaign
            ))
        }

        items.append(contentsOf: [
            .init(
                id: "start_session",
                title: "Start a session",
                subtitle: "Record door outcomes from the campaign map.",
                systemImage: "figure.walk",
                action: .openRecord
            ),
            .init(
                id: "review_leads",
                title: "Review sample leads",
                subtitle: "See how door notes and QR interest become follow-ups.",
                systemImage: "person.text.rectangle.fill",
                action: .openLeads
            ),
            .init(
                id: team ? "view_team_stats" : "create_real_campaign",
                title: team ? "Check team reporting" : "Create your first real campaign",
                subtitle: team ? "Use leaderboard and routes to understand activity." : "Turn the walkthrough into your own territory.",
                systemImage: team ? "chart.bar.fill" : "plus.circle.fill",
                action: team ? .openLeaderboard : .createRealCampaign
            ),
        ])

        if team {
            items.insert(.init(
                id: "assign_work",
                title: "Assign or review work",
                subtitle: "Open routes and assigned campaign work for the team flow.",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                action: .openRoutes
            ), at: min(3, items.count))
        }

        return items
    }

    private static func memberItems(hasAssignedWork: Bool) -> [OnboardingDemoChecklistItem] {
        [
            .init(
                id: "open_assigned_work",
                title: hasAssignedWork ? "Open assigned work" : "Check for assignments",
                subtitle: hasAssignedWork ? "Start with the route or campaign assigned to you." : "Assignments from an owner will appear in routes and session start.",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                action: hasAssignedWork ? .openRoutes : .openRecord
            ),
            .init(
                id: "record_outcomes",
                title: "Record door outcomes",
                subtitle: "Use the session map to mark delivered, talked, or follow-up.",
                systemImage: "checkmark.circle.fill",
                action: .openRecord
            ),
            .init(
                id: "view_member_leads",
                title: "View leads",
                subtitle: "Follow up on contacts created from your route work.",
                systemImage: "person.text.rectangle.fill",
                action: .openLeads
            ),
            .init(
                id: "check_stats",
                title: "Check personal stats",
                subtitle: "See your activity roll up into team reporting.",
                systemImage: "chart.bar.fill",
                action: .openLeaderboard
            ),
        ]
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleUUID(primary: Key, fallback: Key) throws -> UUID? {
        if let uuid = try decodeIfPresent(UUID.self, forKey: primary) {
            return uuid
        }
        if let uuid = try decodeIfPresent(UUID.self, forKey: fallback) {
            return uuid
        }
        if let raw = try decodeIfPresent(String.self, forKey: primary), let uuid = UUID(uuidString: raw) {
            return uuid
        }
        if let raw = try decodeIfPresent(String.self, forKey: fallback), let uuid = UUID(uuidString: raw) {
            return uuid
        }
        return nil
    }

    func decodeFlexibleDate(primary: Key, fallback: Key) throws -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let primaryRaw = try decodeIfPresent(String.self, forKey: primary)
        let fallbackRaw = try decodeIfPresent(String.self, forKey: fallback)
        if let raw = primaryRaw ?? fallbackRaw {
            return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }
        if let date = try? decodeIfPresent(Date.self, forKey: primary) {
            return date
        }
        if let date = try? decodeIfPresent(Date.self, forKey: fallback) {
            return date
        }
        return nil
    }
}
