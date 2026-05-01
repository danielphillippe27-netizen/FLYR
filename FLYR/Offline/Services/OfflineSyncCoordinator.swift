import Foundation
import CoreLocation
import Combine

private enum OutboxProcessingError: LocalizedError {
    case unsupportedOperation(String)
    case invalidPayload(operation: String, entryId: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "Unsupported outbox operation: \(operation)"
        case .invalidPayload(let operation, let entryId):
            return "Invalid payload for outbox operation \(operation) in entry \(entryId)"
        }
    }
}

@MainActor
final class OfflineSyncCoordinator: ObservableObject {
    static let shared = OfflineSyncCoordinator()

    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastSyncAt: Date?

    private let outboxRepository = OutboxRepository.shared
    private let campaignRepository = CampaignRepository.shared
    private let sessionRepository = SessionRepository.shared
    private let contactRepository = ContactRepository.shared
    private let networkMonitor = NetworkMonitor.shared
    private let maxRetryDelaySeconds: TimeInterval = 60
    private let maxRetryAttempts = 8
    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?

    private init() {
        networkMonitor.$isOnline
            .receive(on: RunLoop.main)
            .sink { [weak self] isOnline in
                guard let self else { return }
                if isOnline {
                    self.scheduleProcessOutbox()
                }
            }
            .store(in: &cancellables)
        Task { await refreshPendingCount() }
    }

    func refreshPendingCount() async {
        pendingCount = await outboxRepository.pendingCount()
    }

    func scheduleProcessOutbox() {
        guard processingTask == nil else { return }
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processOutbox()
            self.processingTask = nil
        }
    }

    func processOutbox() async {
        guard networkMonitor.isOnline else {
            await refreshPendingCount()
            return
        }
        guard !isSyncing else { return }

        isSyncing = true
        defer {
            isSyncing = false
            Task { await refreshPendingCount() }
        }

        await outboxRepository.resetStaleProcessing()

        while networkMonitor.isOnline {
            let pending = await outboxRepository.fetchPending(limit: 20)
            guard !pending.isEmpty else { return }

            for entry in pending {
                guard networkMonitor.isOnline else { return }

                await outboxRepository.markAttempted(id: entry.id)

                do {
                    try await process(entry: entry)
                    let syncedAt = Date()
                    lastSyncAt = syncedAt
                    await outboxRepository.markSynced(id: entry.id, at: syncedAt)
                } catch {
                    if entry.clientMutationId != nil, isDuplicateClientMutation(error) {
                        let syncedAt = Date()
                        lastSyncAt = syncedAt
                        await outboxRepository.markSynced(id: entry.id, at: syncedAt)
                        continue
                    }
                    let shouldDeadLetter = isNonRetryable(error) || entry.retryCount + 1 >= maxRetryAttempts
                    let retryAfter = shouldDeadLetter ? nil : Date().addingTimeInterval(retryDelaySeconds(for: entry))
                    await outboxRepository.markFailed(
                        id: entry.id,
                        errorMessage: error.localizedDescription,
                        retryAfter: retryAfter,
                        deadLetter: shouldDeadLetter
                    )
                    if !shouldDeadLetter {
                        scheduleRetryAfterFailure(for: entry)
                    }
                }
            }
        }
    }

    private func process(entry: OutboxEntry) async throws {
        guard let operation = OutboxOperation(rawValue: entry.operation) else {
            throw OutboxProcessingError.unsupportedOperation(entry.operation)
        }

        switch operation {
        case .upsertAddressStatus:
            guard let payload = entry.decodedPayload(AddressStatusOutboxPayload.self),
                  let campaignId = UUID(uuidString: payload.campaignId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            let addressIds = payload.addressIds.compactMap(UUID.init(uuidString:))
            let location = makeLocation(latitude: payload.latitude, longitude: payload.longitude)
            let eventType = payload.sessionEventType.flatMap(SessionEventType.init(rawValue:))
            let status = AddressStatus(rawValue: payload.status) ?? .none
            let sessionId = payload.sessionId.flatMap(UUID.init(uuidString:))
            let occurredAt = OfflineDateCodec.date(from: payload.occurredAt)

            let returnedRows = try await VisitsAPI.shared.performRemoteTargetStatusUpdate(
                addressIds: addressIds,
                campaignId: campaignId,
                status: status,
                notes: payload.notes,
                sessionId: sessionId,
                sessionTargetId: payload.sessionTargetId,
                sessionEventType: eventType,
                location: location,
                occurredAt: occurredAt
            )

            if returnedRows.isEmpty {
                await campaignRepository.markStatusRowsSynced(campaignId: campaignId, addressIds: addressIds)
            } else {
                await campaignRepository.upsertStatuses(rows: returnedRows)
            }
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .upsertAddressCaptureMetadata:
            guard let payload = entry.decodedPayload(AddressCaptureMetadataOutboxPayload.self),
                  let campaignId = UUID(uuidString: payload.campaignId),
                  let addressId = UUID(uuidString: payload.addressId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await VisitsAPI.shared.performRemoteUpsertCampaignAddressCaptureMetadata(
                addressId: addressId,
                campaignId: campaignId,
                contactName: payload.contactName,
                leadStatus: payload.leadStatus,
                productInterest: payload.productInterest,
                followUpDate: OfflineDateCodec.date(from: payload.followUpDate),
                rawTranscript: payload.rawTranscript,
                aiSummary: payload.aiSummary,
                clearAll: payload.clearAll
            )
            await campaignRepository.markAddressCaptureMetadataSynced(
                campaignId: campaignId,
                addressId: addressId
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .logBuildingTouch:
            guard let payload = entry.decodedPayload(BuildingTouchOutboxPayload.self),
                  let addressId = UUID(uuidString: payload.addressId),
                  let campaignId = UUID(uuidString: payload.campaignId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await VisitsAPI.shared.performRemoteLogBuildingTouch(
                addressId: addressId,
                campaignId: campaignId,
                buildingId: payload.buildingId,
                sessionId: payload.sessionId.flatMap(UUID.init(uuidString:)),
                userId: payload.userId.flatMap(UUID.init(uuidString:)),
                touchedAt: OfflineDateCodec.date(from: payload.touchedAt),
                clientMutationId: entry.clientMutationId
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .markAddressVisited:
            guard let payload = entry.decodedPayload(MarkAddressVisitedOutboxPayload.self),
                  let addressId = UUID(uuidString: payload.addressId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await VisitsAPI.shared.performRemoteMarkAddressVisited(
                addressId: addressId,
                visited: payload.visited
            )

        case .createSession:
            guard let payload = entry.decodedPayload(OfflineSessionPayload.self),
                  let sessionId = UUID(uuidString: payload.id),
                  let userId = UUID(uuidString: payload.userId),
                  let campaignId = UUID(uuidString: payload.campaignId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await SessionsAPI.shared.createSession(
                id: sessionId,
                userId: userId,
                campaignId: campaignId,
                targetBuildingIds: payload.targetBuildings,
                autoCompleteEnabled: payload.autoCompleteEnabled,
                thresholdMeters: payload.thresholdMeters,
                dwellSeconds: payload.dwellSeconds,
                notes: payload.notes,
                workspaceId: payload.workspaceId.flatMap(UUID.init(uuidString:)),
                goalType: GoalType(rawValue: payload.goalType) ?? .knocks,
                goalAmount: payload.goalAmount,
                sessionMode: SessionMode(rawValue: payload.sessionMode) ?? .doorKnocking,
                routeAssignmentId: payload.routeAssignmentId.flatMap(UUID.init(uuidString:)),
                farmExecutionContext: payload.farmExecutionContext?.makeContext(),
                startedAt: OfflineDateCodec.date(from: payload.startedAt)
            )
            await sessionRepository.markSessionRemoteCreated(sessionId: sessionId)
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .updateSessionProgress, .endSession:
            guard let payload = entry.decodedPayload(SessionProgressOutboxPayload.self),
                  let sessionId = UUID(uuidString: payload.id) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await SessionsAPI.shared.updateSession(
                id: sessionId,
                completedCount: payload.completedCount,
                distanceM: payload.distanceM,
                activeSeconds: payload.activeSeconds,
                pathGeoJSON: payload.pathGeoJSON,
                pathGeoJSONNormalized: payload.pathGeoJSONNormalized,
                flyersDelivered: payload.flyersDelivered,
                conversations: payload.conversations,
                leadsCreated: payload.leadsCreated,
                appointmentsCount: payload.appointmentsCount,
                doorsHit: payload.doorsHit,
                autoCompleteEnabled: payload.autoCompleteEnabled,
                isPaused: payload.isPaused,
                endTime: OfflineDateCodec.date(from: payload.endTime)
            )
            await sessionRepository.markSessionSynced(id: sessionId)
            if let campaignId = payload.campaignId {
                await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
            }

        case .createSessionEvent:
            guard let payload = entry.decodedPayload(SessionEventOutboxPayload.self),
                  let eventType = SessionEventType(rawValue: payload.eventType),
                  let sessionId = UUID(uuidString: payload.sessionId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            if let buildingId = payload.buildingId, !buildingId.isEmpty {
                try await SessionEventsAPI.shared.logEvent(
                    sessionId: sessionId,
                    buildingId: buildingId,
                    eventType: eventType,
                    lat: payload.latitude ?? 0,
                    lon: payload.longitude ?? 0,
                    metadata: payload.metadata,
                    clientMutationId: entry.clientMutationId
                )
            } else {
                try await SessionEventsAPI.shared.logLifecycleEvent(
                    sessionId: sessionId,
                    eventType: eventType,
                    lat: payload.latitude,
                    lon: payload.longitude,
                    clientMutationId: entry.clientMutationId
                )
            }

            if let eventId = UUID(uuidString: payload.localEventId) {
                await sessionRepository.markSessionEventSynced(eventId: eventId)
            }
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .upsertContact:
            guard let payload = entry.decodedPayload(ContactOutboxPayload.self),
                  let contact = OfflineJSONCodec.decode(Contact.self, from: payload.contactJSON) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            let syncedContact = try await ContactsService.shared.performRemoteUpsertContact(
                contact,
                userID: payload.userId.flatMap(UUID.init(uuidString:)),
                workspaceId: payload.workspaceId.flatMap(UUID.init(uuidString:)),
                addressId: payload.addressId.flatMap(UUID.init(uuidString:)),
                syncToCRM: payload.syncToCRM
            )
            await contactRepository.upsertContacts(
                [syncedContact],
                userId: payload.userId.flatMap(UUID.init(uuidString:)),
                workspaceId: payload.workspaceId.flatMap(UUID.init(uuidString:)),
                dirty: false,
                syncedAt: Date()
            )
            await contactRepository.markContactsSynced(ids: [syncedContact.id])
            if let campaignId = syncedContact.campaignId?.uuidString {
                await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: campaignId)
            }

        case .createContactActivity:
            guard let payload = entry.decodedPayload(ContactActivityOutboxPayload.self),
                  let contactId = UUID(uuidString: payload.contactId),
                  let type = ActivityType(rawValue: payload.type) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            let activity = try await ContactsService.shared.performRemoteLogActivity(
                contactID: contactId,
                type: type,
                note: payload.note,
                timestamp: OfflineDateCodec.date(from: payload.timestamp)
            )
            await contactRepository.upsertActivities([activity], dirty: false, syncedAt: Date())
            if let activityId = UUID(uuidString: payload.localActivityId) {
                await contactRepository.markActivitiesSynced(ids: [activityId])
            }

        case .deleteContact:
            guard let payload = entry.decodedPayload(DeleteContactOutboxPayload.self),
                  let contactId = UUID(uuidString: payload.contactId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await ContactsService.shared.performRemoteDeleteContact(contactId: contactId)

        case .deleteBuilding:
            guard let payload = entry.decodedPayload(DeleteBuildingOutboxPayload.self) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await BuildingLinkService.shared.performRemoteDeleteBuildingAndAddresses(
                campaignId: payload.campaignId,
                buildingId: payload.buildingId
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .moveAddress:
            guard let payload = entry.decodedPayload(MoveAddressOutboxPayload.self),
                  let addressId = UUID(uuidString: payload.addressId) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await BuildingLinkService.shared.performRemoteMoveAddress(
                campaignId: payload.campaignId,
                addressId: addressId,
                coordinate: CLLocationCoordinate2D(
                    latitude: payload.latitude,
                    longitude: payload.longitude
                )
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)

        case .moveBuilding:
            guard let payload = entry.decodedPayload(MoveBuildingOutboxPayload.self),
                  let geometry = OfflineJSONCodec.decode(
                    MapFeatureGeoJSONGeometry.self,
                    from: payload.geometryJSON
                  ) else {
                throw OutboxProcessingError.invalidPayload(operation: entry.operation, entryId: entry.id)
            }

            try await BuildingLinkService.shared.performRemoteMoveBuilding(
                campaignId: payload.campaignId,
                buildingId: payload.buildingId,
                geometry: geometry
            )
            await CampaignDownloadService.shared.recordSuccessfulSync(campaignId: payload.campaignId)
        }
    }

    private func makeLocation(latitude: Double?, longitude: Double?) -> CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func isNonRetryable(_ error: Error) -> Bool {
        error is OutboxProcessingError
    }

    private func isDuplicateClientMutation(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("duplicate") && message.contains("client_mutation")
    }

    private func retryDelaySeconds(for entry: OutboxEntry) -> TimeInterval {
        min(
            maxRetryDelaySeconds,
            max(5, pow(2, Double(min(entry.retryCount + 1, 5))))
        )
    }

    private func scheduleRetryAfterFailure(for entry: OutboxEntry) {
        guard networkMonitor.isOnline else { return }

        let retryDelaySeconds = retryDelaySeconds(for: entry)

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(retryDelaySeconds * 1_000_000_000))
            guard self.networkMonitor.isOnline else { return }
            self.scheduleProcessOutbox()
        }
    }
}
