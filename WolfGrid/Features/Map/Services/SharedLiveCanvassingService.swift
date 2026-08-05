import Foundation
import CoreLocation
import Combine
import Supabase

struct CampaignManualPinRealtimeRow: Decodable {
    let id: UUID
    let address: String?
    let formatted: String?
    let geom: MapFeatureGeoJSONGeometry?
    let matchSource: String?
    let createdBy: UUID?
    let updatedBy: UUID?
    let revision: Int
    let updatedAt: Date?
    let deletedAt: Date?

    var coordinate: CLLocationCoordinate2D? {
        guard let point = geom?.asPoint, point.count >= 2 else { return nil }
        let value = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        return CLLocationCoordinate2DIsValid(value) ? value : nil
    }

    enum CodingKeys: String, CodingKey {
        case id, address, formatted, geom, revision
        case matchSource = "match_source"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        formatted = try container.decodeIfPresent(String.self, forKey: .formatted)
        geom = try container.decodeIfPresent(MapFeatureGeoJSONGeometry.self, forKey: .geom)
        matchSource = try container.decodeIfPresent(String.self, forKey: .matchSource)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        updatedBy = try container.decodeIfPresent(UUID.self, forKey: .updatedBy)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

@MainActor
final class SharedLiveCanvassingService: ObservableObject {
    static let shared = SharedLiveCanvassingService()

    @Published private(set) var isJoined = false
    @Published private(set) var liveCampaignId: UUID?
    @Published private(set) var teammates: [SharedCanvassingTeammate] = []
    @Published private(set) var memberDirectory: [UUID: SharedCanvassingMember] = [:]
    @Published private(set) var homeStatesByAddressId: [UUID: AddressStatusRow] = [:]
    @Published private(set) var manualPinsByAddressId: [UUID: CampaignManualPinRealtimeRow] = [:]
    @Published private(set) var lastJoinError: String?
    @Published private(set) var inviteAvailability: SharedLiveCanvassingAvailability = .unknown

    private let client = SupabaseManager.shared.client
    private let stalenessConfig = SharedLiveCanvassingStalenessConfig.v1
    private let presenceMinInterval: TimeInterval = 15
    private let presenceMinDistanceMeters: CLLocationDistance = 20

    private var presenceChannel: RealtimeChannelV2?
    private var homeStatesChannel: RealtimeChannelV2?
    private var manualPinsChannel: RealtimeChannelV2?
    private var assignmentsChannel: RealtimeChannelV2?
    private var presenceStreamTask: Task<Void, Never>?
    private var homeStatesStreamTask: Task<Void, Never>?
    private var manualPinsStreamTask: Task<Void, Never>?
    private var assignmentsStreamTask: Task<Void, Never>?
    private var stalenessTask: Task<Void, Never>?

    private var currentCampaignId: UUID?
    private var currentSessionId: UUID?
    private var currentUserId: UUID?
    private var presenceRows: [UUID: CampaignPresenceRow] = [:]
    private var lastPublishedAt: Date?
    private var lastPublishedLocation: CLLocation?
    private var lastPublishedStatus: SharedLiveCanvassingPresenceStatus?
    private var inviteAvailabilityCampaignId: UUID?
    private var lastTeamPublishedAt: Date?
    private var lastTeamPublishedLocation: CLLocation?
    private var lastTeamPublishedStatus: SharedLiveCanvassingPresenceStatus?
    private var lastTeamPresenceCampaignId: UUID?
    private var lastTeamPresenceSessionId: UUID?
    private var lastTeamPresenceUserId: UUID?

    private init() {}

    #if DEBUG
    func publishE2EPresence(
        campaignId: UUID,
        sessionId: UUID,
        userId: UUID,
        location: CLLocation
    ) async throws {
        guard SupabaseManager.shared.isLocalE2E, AuthManager.shared.user?.id == userId else {
            throw NSError(domain: "WolfGridE2E", code: 1, userInfo: [NSLocalizedDescriptionKey: "E2E presence requires the authenticated local QA user"])
        }
        let session = try await client.auth.session
        guard session.user.id == userId else {
            throw NSError(domain: "WolfGridE2E", code: 2, userInfo: [NSLocalizedDescriptionKey: "Supabase session user does not match the signed-in QA user"])
        }
        let membershipResponse = try await client
            .rpc("is_campaign_member", params: ["p_campaign_id": campaignId])
            .execute()
        guard try JSONDecoder().decode(Bool.self, from: membershipResponse.data) else {
            throw NSError(domain: "WolfGridE2E", code: 3, userInfo: [NSLocalizedDescriptionKey: "Authenticated QA user cannot view the seeded campaign"])
        }
        let payload: [String: AnyCodable] = [
            "campaign_id": AnyCodable(campaignId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "session_id": AnyCodable(sessionId.uuidString),
            "lat": AnyCodable(location.coordinate.latitude),
            "lng": AnyCodable(location.coordinate.longitude),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "status": AnyCodable(SharedLiveCanvassingPresenceStatus.active.rawValue)
        ]
        _ = try await client
            .from("campaign_presence")
            .upsert(payload, onConflict: "campaign_id,user_id")
            .execute()
    }
    #endif

    func inviteAvailability(for campaignId: UUID?) -> SharedLiveCanvassingAvailability {
        guard let campaignId, inviteAvailabilityCampaignId == campaignId else {
            return .unknown
        }
        return inviteAvailability
    }

    func refreshInviteAvailability(
        campaignId: UUID,
        force: Bool = false
    ) async {
        guard NetworkMonitor.shared.isOnline else {
            inviteAvailabilityCampaignId = campaignId
            inviteAvailability = .unavailable
            return
        }

        if isJoined, liveCampaignId == campaignId {
            inviteAvailabilityCampaignId = campaignId
            inviteAvailability = .available
            return
        }

        let scopedAvailability = inviteAvailability(for: campaignId)
        if !force, scopedAvailability != .unknown {
            return
        }

        inviteAvailabilityCampaignId = campaignId
        inviteAvailability = .unknown

        do {
            try await probeInviteAvailability(campaignId: campaignId)
            guard inviteAvailabilityCampaignId == campaignId else { return }
            inviteAvailability = .available
        } catch is CancellationError {
            return
        } catch {
            guard inviteAvailabilityCampaignId == campaignId else { return }
            let normalizedError = normalizeJoinError(error)
            if let sharedLiveError = normalizedError as? SharedLiveCanvassingError,
               case .unavailable = sharedLiveError {
                inviteAvailability = .unavailable
            } else {
                inviteAvailability = .unknown
            }
        }
    }

    func join(
        campaignId: UUID,
        sessionId: UUID,
        initialLocation: CLLocation? = nil
    ) async throws {
        guard NetworkMonitor.shared.isOnline else {
            inviteAvailabilityCampaignId = campaignId
            inviteAvailability = .unavailable
            throw SharedLiveCanvassingError.unavailable
        }

        guard let currentUser = AuthManager.shared.user else {
            throw SharedLiveCanvassingError.notAuthenticated
        }

        if isJoined,
           currentCampaignId == campaignId,
           currentSessionId == sessionId,
           currentUserId == currentUser.id {
            inviteAvailabilityCampaignId = campaignId
            inviteAvailability = .available
            try await upsertPresence(status: .active, location: initialLocation, force: true)
            return
        }

        inviteAvailabilityCampaignId = campaignId
        inviteAvailability = .unknown
        await disconnect(deletePresence: true)

        do {
            let directory = try await fetchMemberDirectory(campaignId: campaignId, currentUser: currentUser)
            currentCampaignId = campaignId
            currentSessionId = sessionId
            currentUserId = currentUser.id
            memberDirectory = directory

            try await upsertPresence(status: .active, location: initialLocation, force: true)
            try await subscribePresence(campaignId: campaignId)
            try await subscribeHomeStates(campaignId: campaignId)
            try await subscribeManualPins(campaignId: campaignId)
            try await subscribeAssignmentInvalidations(campaignId: campaignId)
            try await refreshHomeStatesSnapshot(campaignId: campaignId)
            try await refreshManualPinsSnapshot(campaignId: campaignId)
            try await refreshPresenceSnapshot(campaignId: campaignId)

            liveCampaignId = campaignId
            isJoined = true
            lastJoinError = nil
            inviteAvailability = .available
            startStalenessLoop()
        } catch {
            let normalizedError = normalizeJoinError(error)
            lastJoinError = normalizedError.localizedDescription
            if let sharedLiveError = normalizedError as? SharedLiveCanvassingError,
               case .unavailable = sharedLiveError {
                inviteAvailability = .unavailable
            } else {
                inviteAvailability = .unknown
            }
            await disconnect(deletePresence: true)
            throw normalizedError
        }
    }

    func joinNonFatal(
        campaignId: UUID,
        sessionId: UUID,
        initialLocation: CLLocation? = nil
    ) async -> SharedLiveCanvassingStartOutcome {
        guard NetworkMonitor.shared.isOnline else {
            inviteAvailabilityCampaignId = campaignId
            inviteAvailability = .unavailable
            return .continueSolo(reason: "Offline. Shared live canvassing will reconnect when you're back online.")
        }

        do {
            try await join(campaignId: campaignId, sessionId: sessionId, initialLocation: initialLocation)
            return .joined
        } catch {
            lastJoinError = error.localizedDescription
            return SharedLiveCanvassingReducer.nonFatalJoinOutcome(for: error)
        }
    }

    func publishPresence(
        location: CLLocation?,
        isPaused: Bool,
        force: Bool = false
    ) async {
        guard isJoined else { return }

        let nextStatus: SharedLiveCanvassingPresenceStatus = isPaused ? .paused : .active
        let now = Date()
        let locationToPersist = location ?? lastPublishedLocation
        let statusChanged = nextStatus != lastPublishedStatus
        let timeReady = lastPublishedAt.map { now.timeIntervalSince($0) >= presenceMinInterval } ?? true
        let movedEnough = {
            guard let locationToPersist, let lastPublishedLocation else { return locationToPersist != nil }
            return locationToPersist.distance(from: lastPublishedLocation) >= presenceMinDistanceMeters
        }()

        guard force || statusChanged || timeReady || movedEnough else { return }

        do {
            try await upsertPresence(status: nextStatus, location: locationToPersist, force: true)
        } catch {
            print("⚠️ [SharedLive] Failed to publish presence: \(error)")
        }
    }

    func publishTeamPresence(
        campaignId: UUID?,
        sessionId: UUID?,
        userId: UUID?,
        location: CLLocation?,
        isPaused: Bool,
        force: Bool = false
    ) async {
        guard NetworkMonitor.shared.isOnline,
              let campaignId,
              let sessionId,
              let userId else { return }

        let nextStatus: SharedLiveCanvassingPresenceStatus = isPaused ? .paused : .active
        let now = Date()
        let locationToPersist = location ?? lastTeamPublishedLocation
        let statusChanged = nextStatus != lastTeamPublishedStatus
        let sessionChanged = lastTeamPresenceSessionId != sessionId
            || lastTeamPresenceCampaignId != campaignId
            || lastTeamPresenceUserId != userId
        let timeReady = lastTeamPublishedAt.map { now.timeIntervalSince($0) >= presenceMinInterval } ?? true
        let movedEnough = {
            guard let locationToPersist, let lastTeamPublishedLocation else { return locationToPersist != nil }
            return locationToPersist.distance(from: lastTeamPublishedLocation) >= presenceMinDistanceMeters
        }()

        guard force || sessionChanged || statusChanged || timeReady || movedEnough else { return }

        let payload: [String: AnyCodable] = [
            "campaign_id": AnyCodable(campaignId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "session_id": AnyCodable(sessionId.uuidString),
            "lat": AnyCodable(locationToPersist?.coordinate.latitude as Any),
            "lng": AnyCodable(locationToPersist?.coordinate.longitude as Any),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: now)),
            "status": AnyCodable(nextStatus.rawValue)
        ]

        do {
            _ = try await client
                .from("campaign_presence")
                .upsert(payload, onConflict: "campaign_id,user_id")
                .execute()

            lastTeamPresenceCampaignId = campaignId
            lastTeamPresenceSessionId = sessionId
            lastTeamPresenceUserId = userId
            if locationToPersist != nil {
                lastTeamPublishedLocation = locationToPersist
            }
            lastTeamPublishedAt = now
            lastTeamPublishedStatus = nextStatus
        } catch {
            if !isMissingSharedLiveInfrastructure(error) {
                print("⚠️ [SharedLive] Failed to publish team presence: \(error)")
            }
        }
    }

    func clearTeamPresence(campaignId: UUID?, userId: UUID?) async {
        guard NetworkMonitor.shared.isOnline,
              let campaignId,
              let userId else { return }

        do {
            _ = try await client
                .from("campaign_presence")
                .delete()
                .eq("campaign_id", value: campaignId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            if !isMissingSharedLiveInfrastructure(error) {
                print("⚠️ [SharedLive] Failed to clear team presence: \(error)")
            }
        }

        if lastTeamPresenceCampaignId == campaignId, lastTeamPresenceUserId == userId {
            lastTeamPublishedAt = nil
            lastTeamPublishedLocation = nil
            lastTeamPublishedStatus = nil
            lastTeamPresenceCampaignId = nil
            lastTeamPresenceSessionId = nil
            lastTeamPresenceUserId = nil
        }
    }

    func leaveCurrentSession() async {
        inviteAvailabilityCampaignId = nil
        inviteAvailability = .unknown
        lastJoinError = nil
        await disconnect(deletePresence: true)
    }

    /// Observe collaborative house state whenever an authorized campaign map is open,
    /// even when the user has not started a GPS/shared session.
    func observeCampaign(campaignId: UUID) async {
        guard NetworkMonitor.shared.isOnline,
              let currentUser = AuthManager.shared.user else { return }
        if isJoined, currentCampaignId == campaignId {
            try? await refreshHomeStatesSnapshot(campaignId: campaignId)
            try? await refreshManualPinsSnapshot(campaignId: campaignId)
            try? await refreshPresenceSnapshot(campaignId: campaignId)
            return
        }
        if currentCampaignId == campaignId, homeStatesChannel != nil {
            try? await refreshHomeStatesSnapshot(campaignId: campaignId)
            try? await refreshManualPinsSnapshot(campaignId: campaignId)
            return
        }
        if isJoined { return }

        await disconnect(deletePresence: false)
        do {
            currentCampaignId = campaignId
            currentUserId = currentUser.id
            memberDirectory = try await fetchMemberDirectory(
                campaignId: campaignId,
                currentUser: currentUser
            )
            try await subscribeHomeStates(campaignId: campaignId)
            try await subscribeManualPins(campaignId: campaignId)
            try await subscribeAssignmentInvalidations(campaignId: campaignId)
            try await refreshHomeStatesSnapshot(campaignId: campaignId)
            try await refreshManualPinsSnapshot(campaignId: campaignId)
            liveCampaignId = campaignId
        } catch {
            lastJoinError = error.localizedDescription
            await disconnect(deletePresence: false)
        }
    }

    func stopObservingCampaign(campaignId: UUID) async {
        guard !isJoined, currentCampaignId == campaignId else { return }
        await disconnect(deletePresence: false)
    }

    func clearHomeStateCache() {
        homeStatesByAddressId = [:]
    }

    private func disconnect(deletePresence: Bool) async {
        let campaignId = currentCampaignId
        let userId = currentUserId
        let shouldDeletePresence = deletePresence && NetworkMonitor.shared.isOnline

        presenceStreamTask?.cancel()
        presenceStreamTask = nil
        homeStatesStreamTask?.cancel()
        homeStatesStreamTask = nil
        manualPinsStreamTask?.cancel()
        manualPinsStreamTask = nil
        assignmentsStreamTask?.cancel()
        assignmentsStreamTask = nil
        stalenessTask?.cancel()
        stalenessTask = nil

        if let presenceChannel {
            await presenceChannel.unsubscribe()
            self.presenceChannel = nil
        }
        if let homeStatesChannel {
            await homeStatesChannel.unsubscribe()
            self.homeStatesChannel = nil
        }
        if let manualPinsChannel {
            await manualPinsChannel.unsubscribe()
            self.manualPinsChannel = nil
        }
        if let assignmentsChannel {
            await assignmentsChannel.unsubscribe()
            self.assignmentsChannel = nil
        }

        if shouldDeletePresence, let campaignId, let userId {
            do {
                _ = try await client
                    .from("campaign_presence")
                    .delete()
                    .eq("campaign_id", value: campaignId.uuidString)
                    .eq("user_id", value: userId.uuidString)
                    .execute()
            } catch {
                print("⚠️ [SharedLive] Failed to delete presence row: \(error)")
            }
        }

        currentCampaignId = nil
        currentSessionId = nil
        currentUserId = nil
        presenceRows = [:]
        teammates = []
        memberDirectory = [:]
        liveCampaignId = nil
        isJoined = false
        lastPublishedAt = nil
        lastPublishedLocation = nil
        lastPublishedStatus = nil
        homeStatesByAddressId = [:]
        manualPinsByAddressId = [:]
    }

    private func fetchMemberDirectory(
        campaignId: UUID,
        currentUser: AppUser
    ) async throws -> [UUID: SharedCanvassingMember] {
        do {
            let rows = try await fetchDirectoryViaRPC(campaignId: campaignId)
            guard rows.contains(where: { $0.userId == currentUser.id }) else {
                throw SharedLiveCanvassingError.notCampaignMember
            }
            let members = rows.map(SharedCanvassingMember.init(row:))
            return Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })
        } catch let error as SharedLiveCanvassingError {
            throw error
        } catch {
            guard isMissingSharedLiveInfrastructure(error) else { throw error }
        }

        do {
            let fallbackRows = try await fetchDirectoryFallback(campaignId: campaignId)
            guard fallbackRows.contains(where: { $0.userId == currentUser.id }) else {
                throw SharedLiveCanvassingError.notCampaignMember
            }

            let fallbackMembers = fallbackRows.map { row in
                let displayName: String
                let avatarURL: String?

                if row.userId == currentUser.id {
                    displayName = currentUser.displayName ?? currentUser.email
                    avatarURL = currentUser.photoURL?.absoluteString
                } else {
                    displayName = "Rep \(row.userId.uuidString.prefix(4))"
                    avatarURL = nil
                }

                return SharedCanvassingMember(
                    userId: row.userId,
                    role: row.role,
                    displayName: displayName,
                    email: nil,
                    avatarURL: avatarURL,
                    createdAt: row.createdAt
                )
            }

            return Dictionary(uniqueKeysWithValues: fallbackMembers.map { ($0.userId, $0) })
        } catch {
            guard isMissingLegacyCampaignMemberInfra(error) else {
                throw error
            }
            return try await fetchDirectoryViaWorkspaceFallback(campaignId: campaignId, currentUser: currentUser)
        }
    }

    private func fetchDirectoryViaRPC(campaignId: UUID) async throws -> [CampaignMemberDirectoryRow] {
        let params: [String: AnyCodable] = [
            "p_campaign_id": AnyCodable(campaignId)
        ]
        let response = try await client
            .rpc("rpc_get_campaign_member_directory", params: params)
            .execute()
        return try JSONDecoder.supabaseDates.decode([CampaignMemberDirectoryRow].self, from: response.data)
    }

    private func fetchDirectoryFallback(campaignId: UUID) async throws -> [CampaignMemberFallbackRow] {
        let response = try await client
            .from("campaign_members")
            .select("user_id, role, created_at")
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        return try JSONDecoder.supabaseDates.decode([CampaignMemberFallbackRow].self, from: response.data)
    }

    private func fetchDirectoryViaWorkspaceFallback(
        campaignId: UUID,
        currentUser: AppUser
    ) async throws -> [UUID: SharedCanvassingMember] {
        let response = try await client
            .from("campaigns")
            .select("owner_id, workspace_id, created_at")
            .eq("id", value: campaignId.uuidString)
            .single()
            .execute()

        let campaign = try JSONDecoder.supabaseDates.decode(CampaignWorkspaceFallbackRow.self, from: response.data)

        var membersByUserId: [UUID: SharedCanvassingMember] = [
            campaign.ownerId: fallbackMember(
                userId: campaign.ownerId,
                role: "owner",
                createdAt: campaign.createdAt,
                currentUser: currentUser
            )
        ]

        if let workspaceId = campaign.workspaceId {
            let workspaceResponse = try await client
                .from("workspace_members")
                .select("user_id, role, created_at")
                .eq("workspace_id", value: workspaceId.uuidString)
                .execute()
            let workspaceRows = try JSONDecoder.supabaseDates.decode([WorkspaceMemberFallbackRow].self, from: workspaceResponse.data)

            for row in workspaceRows {
                membersByUserId[row.userId] = fallbackMember(
                    userId: row.userId,
                    role: row.role,
                    createdAt: row.createdAt,
                    currentUser: currentUser
                )
            }
        }

        guard membersByUserId[currentUser.id] != nil else {
            throw SharedLiveCanvassingError.notCampaignMember
        }

        return membersByUserId
    }

    private func fallbackMember(
        userId: UUID,
        role: String,
        createdAt: Date,
        currentUser: AppUser
    ) -> SharedCanvassingMember {
        let isCurrentUser = userId == currentUser.id
        let displayName = isCurrentUser
            ? (currentUser.displayName ?? currentUser.email)
            : "Rep \(userId.uuidString.prefix(4))"

        return SharedCanvassingMember(
            userId: userId,
            role: role,
            displayName: displayName,
            email: isCurrentUser ? currentUser.email : nil,
            avatarURL: isCurrentUser ? currentUser.photoURL?.absoluteString : nil,
            createdAt: createdAt
        )
    }

    private func normalizeJoinError(_ error: Error) -> Error {
        if isMissingSharedLiveInfrastructure(error) {
            return SharedLiveCanvassingError.unavailable
        }
        return error
    }

    private func isMissingLegacyCampaignMemberInfra(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("campaign_members")
            || message.contains("rpc_get_campaign_member_directory")
    }

    private func isMissingSharedLiveInfrastructure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return (message.contains("schema cache") || message.contains("does not exist") || message.contains("could not find the"))
            && (message.contains("campaign_members")
                || message.contains("campaign_presence")
                || message.contains("rpc_get_campaign_member_directory")
                || message.contains("campaign_home_states"))
    }

    private func upsertPresence(
        status: SharedLiveCanvassingPresenceStatus,
        location: CLLocation?,
        force: Bool
    ) async throws {
        guard let campaignId = currentCampaignId,
              let sessionId = currentSessionId,
              let userId = currentUserId else {
            return
        }

        let now = Date()
        let payload: [String: AnyCodable] = [
            "campaign_id": AnyCodable(campaignId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "session_id": AnyCodable(sessionId.uuidString),
            "lat": AnyCodable(location?.coordinate.latitude as Any),
            "lng": AnyCodable(location?.coordinate.longitude as Any),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: now)),
            "status": AnyCodable(status.rawValue)
        ]

        _ = try await client
            .from("campaign_presence")
            .upsert(payload, onConflict: "campaign_id,user_id")
            .execute()

        let row = CampaignPresenceRow(
            campaignId: campaignId,
            userId: userId,
            sessionId: sessionId,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            updatedAt: now,
            status: status
        )

        presenceRows = SharedLiveCanvassingReducer.mergePresence(row, into: presenceRows)
        recomputeTeammates(now: now)

        if force || location != nil {
            lastPublishedLocation = location
        }
        lastPublishedAt = now
        lastPublishedStatus = status
    }

    private func probeInviteAvailability(campaignId: UUID) async throws {
        _ = try await client
            .from("campaign_presence")
            .select("campaign_id")
            .eq("campaign_id", value: campaignId.uuidString)
            .limit(1)
            .execute()
    }

    private func subscribePresence(campaignId: UUID) async throws {
        let channel = client.channel("campaign-presence-\(campaignId.uuidString)")
        let updates = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "campaign_presence",
            filter: .eq("campaign_id", value: campaignId.uuidString)
        )

        presenceStreamTask = Task { [weak self] in
            guard let self else { return }
            for await action in updates {
                await self.handlePresenceAction(action)
            }
        }

        try await channel.subscribeWithError()
        presenceChannel = channel
    }

    private func subscribeHomeStates(campaignId: UUID) async throws {
        let channel = client.channel("campaign-home-states-\(campaignId.uuidString)")
        let updates = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "address_statuses",
            filter: .eq("campaign_id", value: campaignId.uuidString)
        )

        homeStatesStreamTask = Task { [weak self] in
            guard let self else { return }
            for await action in updates {
                await self.handleHomeStateAction(action)
            }
        }

        try await channel.subscribeWithError()
        homeStatesChannel = channel
    }

    private func subscribeManualPins(campaignId: UUID) async throws {
        let channel = client.channel("campaign-manual-pins-\(campaignId.uuidString)")
        let updates = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "campaign_addresses",
            filter: .eq("campaign_id", value: campaignId.uuidString)
        )

        manualPinsStreamTask = Task { [weak self] in
            guard let self else { return }
            for await action in updates {
                await self.handleManualPinAction(action)
            }
        }

        try await channel.subscribeWithError()
        manualPinsChannel = channel
    }

    private func subscribeAssignmentInvalidations(campaignId: UUID) async throws {
        let channel = client.channel("campaign-assignment-invalidations-\(campaignId.uuidString)")
        let updates = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "campaign_assignments",
            filter: .eq("campaign_id", value: campaignId.uuidString)
        )

        assignmentsStreamTask = Task { [weak self] in
            guard let self else { return }
            for await _ in updates {
                await self.reauthorizeObservedCampaign(campaignId: campaignId)
            }
        }

        try await channel.subscribeWithError()
        assignmentsChannel = channel
    }

    private func refreshPresenceSnapshot(campaignId: UUID) async throws {
        var query = client
            .from("campaign_presence")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
        if let currentSessionId {
            query = query.eq("session_id", value: currentSessionId.uuidString)
        }
        let response = try await query.execute()
        let rows = try JSONDecoder.supabaseDates.decode([CampaignPresenceRow].self, from: response.data)
        for row in rows {
            presenceRows = SharedLiveCanvassingReducer.mergePresence(row, into: presenceRows)
        }
        recomputeTeammates(now: Date())
    }

    private func refreshHomeStatesSnapshot(campaignId: UUID) async throws {
        let response = try await client
            .from("address_statuses")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        let rows = try JSONDecoder.supabaseDates.decode([AddressStatusRow].self, from: response.data)
        var merged = homeStatesByAddressId
        for row in rows {
            merged = SharedLiveCanvassingReducer.mergeHomeState(row, into: merged)
        }
        homeStatesByAddressId = merged
    }

    private func refreshManualPinsSnapshot(campaignId: UUID) async throws {
        let response = try await client
            .from("campaign_addresses")
            .select("id,address,formatted,geom,match_source,created_by,updated_by,revision,updated_at,deleted_at")
            .eq("campaign_id", value: campaignId.uuidString)
            .eq("match_source", value: "field_manual_pin")
            .execute()
        let rows = try JSONDecoder.supabaseDates.decode([CampaignManualPinRealtimeRow].self, from: response.data)
        var merged = manualPinsByAddressId
        for row in rows {
            if let current = merged[row.id], current.revision > row.revision { continue }
            merged[row.id] = row
        }
        manualPinsByAddressId = merged
    }

    private func recomputeTeammates(now: Date) {
        teammates = SharedLiveCanvassingReducer.teammates(
            from: presenceRows,
            directory: memberDirectory,
            currentUserId: currentUserId,
            currentSessionId: currentSessionId,
            now: now,
            config: stalenessConfig
        )
    }

    private func startStalenessLoop() {
        stalenessTask?.cancel()
        stalenessTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self.recomputeTeammates(now: Date())
            }
        }
    }

    private func handlePresenceAction(_ action: AnyAction) async {
        switch action {
        case .insert(let insert):
            if let row = try? insert.decodeRecord(as: CampaignPresenceRow.self, decoder: JSONDecoder.supabaseDates) {
                presenceRows = SharedLiveCanvassingReducer.mergePresence(row, into: presenceRows)
            }
        case .update(let update):
            if let row = try? update.decodeRecord(as: CampaignPresenceRow.self, decoder: JSONDecoder.supabaseDates) {
                presenceRows = SharedLiveCanvassingReducer.mergePresence(row, into: presenceRows)
            }
        case .delete(let delete):
            guard let userId = delete.oldRecord["user_id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                return
            }
            presenceRows.removeValue(forKey: userId)
        }

        recomputeTeammates(now: Date())
    }

    private func handleHomeStateAction(_ action: AnyAction) async {
        switch action {
        case .insert(let insert):
            if let row = try? insert.decodeRecord(as: AddressStatusRow.self, decoder: JSONDecoder.supabaseDates) {
                homeStatesByAddressId = SharedLiveCanvassingReducer.mergeHomeState(row, into: homeStatesByAddressId)
            }
        case .update(let update):
            if let row = try? update.decodeRecord(as: AddressStatusRow.self, decoder: JSONDecoder.supabaseDates) {
                homeStatesByAddressId = SharedLiveCanvassingReducer.mergeHomeState(row, into: homeStatesByAddressId)
            }
        case .delete(let delete):
            if let row = try? delete.decodeOldRecord(as: AddressStatusRow.self, decoder: JSONDecoder.supabaseDates) {
                homeStatesByAddressId.removeValue(forKey: row.addressId)
            }
        }
    }

    private func handleManualPinAction(_ action: AnyAction) async {
        let row: CampaignManualPinRealtimeRow?
        switch action {
        case .insert(let insert):
            row = try? insert.decodeRecord(as: CampaignManualPinRealtimeRow.self, decoder: JSONDecoder.supabaseDates)
        case .update(let update):
            row = try? update.decodeRecord(as: CampaignManualPinRealtimeRow.self, decoder: JSONDecoder.supabaseDates)
        case .delete:
            // Versioned clients soft-delete pins, preserving the revision and audit record.
            row = nil
        }
        guard let row, row.matchSource?.lowercased() == "field_manual_pin" else { return }
        if let current = manualPinsByAddressId[row.id], current.revision > row.revision { return }
        manualPinsByAddressId[row.id] = row
    }

    private func reauthorizeObservedCampaign(campaignId: UUID) async {
        guard currentCampaignId == campaignId,
              let currentUser = AuthManager.shared.user,
              currentUser.id == currentUserId else { return }
        do {
            memberDirectory = try await fetchMemberDirectory(
                campaignId: campaignId,
                currentUser: currentUser
            )
            try await refreshHomeStatesSnapshot(campaignId: campaignId)
            try await refreshManualPinsSnapshot(campaignId: campaignId)
        } catch {
            await disconnect(deletePresence: isJoined)
        }
    }
}

private extension SharedLiveCanvassingService {
    struct CampaignWorkspaceFallbackRow: Decodable {
        let ownerId: UUID
        let workspaceId: UUID?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case ownerId = "owner_id"
            case workspaceId = "workspace_id"
            case createdAt = "created_at"
        }
    }

    struct CampaignMemberFallbackRow: Decodable {
        let userId: UUID
        let role: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case role
            case createdAt = "created_at"
        }
    }

    struct WorkspaceMemberFallbackRow: Decodable {
        let userId: UUID
        let role: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case role
            case createdAt = "created_at"
        }
    }

    enum SharedLiveCanvassingError: LocalizedError {
        case notAuthenticated
        case notCampaignMember
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Authentication is required for shared canvassing."
            case .notCampaignMember:
                return "You are not a member of this campaign."
            case .unavailable:
                return "Live session invites are not available on this workspace yet."
            }
        }
    }
}
