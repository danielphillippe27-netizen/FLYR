import Foundation
import Combine
import CoreLocation
import CryptoKit
import Supabase
import UserNotifications
import UIKit

enum SafetyCheckInInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off:
            return "Off"
        case .fifteen:
            return "15 min"
        case .thirty:
            return "30 min"
        case .sixty:
            return "60 min"
        }
    }

    var minutes: Int? {
        self == .off ? nil : rawValue
    }
}

struct SessionBeaconShareRecord: Codable, Identifiable {
    let id: UUID
    let session_id: UUID
    let created_by: UUID
    let share_token_hash: String
    let viewer_label: String?
    let expires_at: Date?
    let revoked_at: Date?
    let last_viewed_at: Date?
    let check_in_interval_minutes: Int?
    let created_at: Date
    let updated_at: Date
}

struct SessionBeaconCheckInRecord: Codable {
    let session_id: UUID
    let share_id: UUID?
    let created_by: UUID
    let interval_minutes: Int
    let grace_period_minutes: Int
    let status: String
    let next_prompt_at: Date?
    let last_prompted_at: Date?
    let last_confirmed_at: Date?
    let created_at: Date
    let updated_at: Date
}

struct PendingSafetyCheckIn: Identifiable {
    let id = UUID()
    let dueAt: Date
    let graceDeadline: Date
}

struct PreparedSessionBeaconSetup: Equatable {
    let checkInInterval: SafetyCheckInInterval
}

@MainActor
final class SessionSafetyBeaconService: ObservableObject {
    static let shared = SessionSafetyBeaconService()
    static let defaultShareMessage = "Here's my live location for my next activity! Follow along on FLYR."

    @Published private(set) var currentShare: SessionBeaconShareRecord?
    @Published private(set) var shareURL: URL?
    @Published private(set) var checkInInterval: SafetyCheckInInterval = .off
    @Published private(set) var selectedRecipients: [BeaconContactRecipient]
    @Published private(set) var shareMessage: String
    @Published private(set) var isBusy = false
    @Published private(set) var isSessionAttached = false
    @Published private(set) var preparedSetup: PreparedSessionBeaconSetup?
    @Published var pendingCheckIn: PendingSafetyCheckIn?
    @Published var errorMessage: String?
    @Published var missedCheckInMessage: String?

    private let client = SupabaseManager.shared.client
    private let localStorage = LocalStorage.shared
    private let gracePeriodMinutes = 5
    private let heartbeatMinInterval: TimeInterval = 15
    private let heartbeatMinDistanceMeters: CLLocationDistance = 20
    private let beaconBaseURL: String = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "https://flyrpro.app"
        guard let components = URLComponents(string: raw), components.host == "flyrpro.app" else {
            return raw
        }
        return "https://www.flyrpro.app"
    }()
    private var activeSessionId: UUID?
    private var activeSessionStart: Date?
    private var lastHeartbeatAt: Date?
    private var lastHeartbeatLocation: CLLocation?
    private var lastPromptAt: Date?
    private var graceDeadline: Date?
    private var outstandingMissedCheckInLogged = false
    private var shareLinkRefreshTask: Task<Void, Never>?

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        selectedRecipients = localStorage.loadBeaconRecipients()
        let savedMessage = localStorage.loadBeaconMessage()?.trimmingCharacters(in: .whitespacesAndNewlines)
        shareMessage = savedMessage?.isEmpty == false ? savedMessage! : Self.defaultShareMessage
    }

    var hasActiveShare: Bool {
        currentShare != nil
    }

    var hasPreparedSetup: Bool {
        preparedSetup != nil
    }

    func restoreState(for sessionId: UUID, startTime: Date?) async {
        activeSessionId = sessionId
        activeSessionStart = startTime
        isSessionAttached = true
        errorMessage = nil
        missedCheckInMessage = nil
        outstandingMissedCheckInLogged = false

        do {
            let shares: [SessionBeaconShareRecord] = try await client
                .from("session_shares")
                .select()
                .eq("session_id", value: sessionId.uuidString)
                .is("revoked_at", value: nil)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .decoded(decoder: JSONDecoder.supabaseDates)
            currentShare = shares.first

            if let token = localStorage.loadBeaconToken(for: sessionId) {
                shareURL = makeShareURL(token: token)
            } else {
                shareURL = nil
            }

            let checkIns: [SessionBeaconCheckInRecord] = try await client
                .from("session_checkins")
                .select()
                .eq("session_id", value: sessionId.uuidString)
                .limit(1)
                .execute()
                .decoded(decoder: JSONDecoder.supabaseDates)

            if let checkIn = checkIns.first, checkIn.status != "disabled" {
                checkInInterval = SafetyCheckInInterval(rawValue: checkIn.interval_minutes) ?? .off
                lastPromptAt = checkIn.last_prompted_at
                graceDeadline = checkIn.last_prompted_at?.addingTimeInterval(TimeInterval(checkIn.grace_period_minutes * 60))
                let lastConfirmedAt = checkIn.last_confirmed_at
                if let lastPromptAt,
                   let graceDeadline,
                   (lastConfirmedAt == nil || lastConfirmedAt! < lastPromptAt),
                   Date() < graceDeadline {
                    pendingCheckIn = PendingSafetyCheckIn(dueAt: lastPromptAt, graceDeadline: graceDeadline)
                } else {
                    pendingCheckIn = nil
                }
                await rescheduleNotifications(for: sessionId, from: checkIn.next_prompt_at)
            } else {
                checkInInterval = .off
                lastPromptAt = nil
                graceDeadline = nil
                pendingCheckIn = nil
                cancelNotifications(for: sessionId)
            }
        } catch {
            errorMessage = "Beacon restore failed: \(error.localizedDescription)"
        }

        await autoEnablePreparedSetupIfNeeded()
    }

    func clearState() {
        activeSessionId = nil
        activeSessionStart = nil
        isSessionAttached = false
        currentShare = nil
        shareURL = nil
        checkInInterval = .off
        lastHeartbeatAt = nil
        lastHeartbeatLocation = nil
        lastPromptAt = nil
        graceDeadline = nil
        pendingCheckIn = nil
        errorMessage = nil
        missedCheckInMessage = nil
        outstandingMissedCheckInLogged = false
    }

    func updateDraft(recipients: [BeaconContactRecipient], message: String) {
        selectedRecipients = Array(recipients.prefix(3))
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        shareMessage = trimmedMessage.isEmpty ? Self.defaultShareMessage : trimmedMessage
        localStorage.saveBeaconRecipients(selectedRecipients)
        localStorage.saveBeaconMessage(shareMessage)
    }

    func prepareForNextSession(viewerLabel: String? = nil, checkInInterval: SafetyCheckInInterval) {
        preparedSetup = PreparedSessionBeaconSetup(
            checkInInterval: checkInInterval
        )
        errorMessage = nil
    }

    func clearPreparedSetup() {
        preparedSetup = nil
    }

    func createOrRefreshShareLink(viewerLabel: String? = nil) async {
        if let shareLinkRefreshTask {
            await shareLinkRefreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCreateOrRefreshShareLink(viewerLabel: viewerLabel)
        }
        shareLinkRefreshTask = task
        await task.value
        shareLinkRefreshTask = nil
    }

    /// Serializes share creation so "toggle on" and "send link" can reuse the same in-flight work.
    private func performCreateOrRefreshShareLink(viewerLabel: String? = nil) async {
        guard let sessionId = activeSessionId else {
            errorMessage = "Start a session before turning on Beacon."
            return
        }
        guard let userId = AuthManager.shared.user?.id else {
            errorMessage = "Sign in again to create a Beacon link."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await revokeActiveShare(logEvent: false)

            let token = randomToken()
            let hash = md5Hex(token)
            let now = Date()
            let resolvedViewerLabel = normalizedViewerLabel(from: viewerLabel)
            var payload: [String: AnyCodable] = [
                "session_id": AnyCodable(sessionId.uuidString),
                "created_by": AnyCodable(userId.uuidString),
                "share_token_hash": AnyCodable(hash),
                "viewer_label": AnyCodable(resolvedViewerLabel as Any),
                "created_at": AnyCodable(ISO8601DateFormatter().string(from: now)),
            ]
            if let minutes = checkInInterval.minutes {
                payload["check_in_interval_minutes"] = AnyCodable(minutes)
            }

            let created: SessionBeaconShareRecord = try await client
                .from("session_shares")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            currentShare = created
            shareURL = makeShareURL(token: token)
            localStorage.saveBeaconToken(token, for: sessionId)

            if let minutes = checkInInterval.minutes {
                try await upsertCheckIn(sessionId: sessionId, shareId: created.id, userId: userId, intervalMinutes: minutes, confirmedAt: now)
            }

            try await logSafetyEvent(
                sessionId: sessionId,
                shareId: created.id,
                userId: userId,
                type: "share_started",
                location: nil,
                message: "Beacon sharing started"
            )
        } catch {
            errorMessage = "Couldn't create Beacon link: \(error.localizedDescription)"
        }
    }

    func revokeActiveShare(logEvent: Bool = true) async throws {
        guard let sessionId = activeSessionId else { return }
        guard let userId = AuthManager.shared.user?.id else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())

        _ = try await client
            .from("session_shares")
            .update(["revoked_at": AnyCodable(timestamp)])
            .eq("session_id", value: sessionId.uuidString)
            .is("revoked_at", value: nil)
            .execute()

        if logEvent, let shareId = currentShare?.id {
            try? await logSafetyEvent(
                sessionId: sessionId,
                shareId: shareId,
                userId: userId,
                type: "share_stopped",
                location: nil,
                message: "Beacon sharing stopped"
            )
        }

        localStorage.clearBeaconToken(for: sessionId)
        currentShare = nil
        shareURL = nil
    }

    func updateCheckInInterval(_ interval: SafetyCheckInInterval) async {
        guard let sessionId = activeSessionId else {
            errorMessage = "Start a session before enabling check-ins."
            return
        }
        guard let userId = AuthManager.shared.user?.id else {
            errorMessage = "Sign in again to update check-ins."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            checkInInterval = interval
            if let minutes = interval.minutes {
                try await requestNotificationPermission()
                let now = Date()
                try await upsertCheckIn(
                    sessionId: sessionId,
                    shareId: currentShare?.id,
                    userId: userId,
                    intervalMinutes: minutes,
                    confirmedAt: now
                )
                await rescheduleNotifications(for: sessionId, from: now.addingTimeInterval(TimeInterval(minutes * 60)))
            } else {
                _ = try await client
                    .from("session_checkins")
                    .delete()
                    .eq("session_id", value: sessionId.uuidString)
                    .execute()
                cancelNotifications(for: sessionId)
                pendingCheckIn = nil
                lastPromptAt = nil
                graceDeadline = nil
            }

            if let shareId = currentShare?.id {
                var data: [String: AnyCodable] = [:]
                if let minutes = interval.minutes {
                    data["check_in_interval_minutes"] = AnyCodable(minutes)
                } else {
                    data["check_in_interval_minutes"] = AnyCodable(NSNull())
                }
                _ = try await client
                    .from("session_shares")
                    .update(data)
                    .eq("id", value: shareId.uuidString)
                    .execute()
            }
        } catch {
            errorMessage = "Couldn't update safety check-ins: \(error.localizedDescription)"
        }
    }

    func confirmCheckIn(location: CLLocation?) async {
        guard let sessionId = activeSessionId,
              let userId = AuthManager.shared.user?.id,
              let minutes = checkInInterval.minutes else {
            pendingCheckIn = nil
            return
        }

        do {
            let now = Date()
            try await upsertCheckIn(
                sessionId: sessionId,
                shareId: currentShare?.id,
                userId: userId,
                intervalMinutes: minutes,
                confirmedAt: now
            )
            try await logSafetyEvent(
                sessionId: sessionId,
                shareId: currentShare?.id,
                userId: userId,
                type: "check_in_confirmed",
                location: location,
                message: "Check-in confirmed"
            )
            pendingCheckIn = nil
            graceDeadline = nil
            lastPromptAt = nil
            outstandingMissedCheckInLogged = false
            missedCheckInMessage = nil
            await rescheduleNotifications(for: sessionId, from: now.addingTimeInterval(TimeInterval(minutes * 60)))
        } catch {
            errorMessage = "Couldn't confirm check-in: \(error.localizedDescription)"
        }
    }

    func recordHeartbeat(location: CLLocation, isPaused: Bool) async {
        guard let sessionId = activeSessionId else { return }
        let requiresHeartbeat = currentShare != nil || checkInInterval != .off
        guard requiresHeartbeat else { return }

        let now = Date()
        if let lastHeartbeatAt,
           now.timeIntervalSince(lastHeartbeatAt) < heartbeatMinInterval,
           let lastHeartbeatLocation,
           lastHeartbeatLocation.distance(from: location) < heartbeatMinDistanceMeters {
            await evaluateCheckInState(now: now, location: location)
            return
        }

        let movementState = resolvedMovementState(for: location, isPaused: isPaused)
        let deviceStatus: [String: AnyCodable] = [
            "horizontal_accuracy": AnyCodable(location.horizontalAccuracy),
            "speed": AnyCodable(location.speed),
            "timestamp": AnyCodable(location.timestamp),
        ]
        let payload: [String: AnyCodable] = [
            "session_id": AnyCodable(sessionId.uuidString),
            "share_id": AnyCodable(currentShare?.id.uuidString as Any),
            "lat": AnyCodable(location.coordinate.latitude),
            "lon": AnyCodable(location.coordinate.longitude),
            "battery_level": AnyCodable(batteryLevel as Any),
            "movement_state": AnyCodable(movementState),
            "device_status": AnyCodable(deviceStatus)
        ]

        do {
            _ = try await client
                .from("session_heartbeats")
                .insert(payload)
                .execute()
            lastHeartbeatAt = now
            lastHeartbeatLocation = location
        } catch {
            errorMessage = "Beacon heartbeat failed: \(error.localizedDescription)"
        }

        await evaluateCheckInState(now: now, location: location)
    }

    func endSession(location: CLLocation?) async {
        guard let sessionId = activeSessionId else {
            clearState()
            return
        }

        do {
            try await revokeActiveShare()
        } catch {
            errorMessage = "Couldn't revoke Beacon on session end: \(error.localizedDescription)"
        }

        _ = try? await client
            .from("session_checkins")
            .delete()
            .eq("session_id", value: sessionId.uuidString)
            .execute()

        cancelNotifications(for: sessionId)
        localStorage.clearBeaconToken(for: sessionId)
        clearState()
        if let location {
            lastHeartbeatLocation = location
        }
    }

    private func upsertCheckIn(
        sessionId: UUID,
        shareId: UUID?,
        userId: UUID,
        intervalMinutes: Int,
        confirmedAt: Date
    ) async throws {
        let nextPrompt = confirmedAt.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        let row: [String: AnyCodable] = [
            "session_id": AnyCodable(sessionId.uuidString),
            "share_id": AnyCodable(shareId?.uuidString as Any),
            "created_by": AnyCodable(userId.uuidString),
            "interval_minutes": AnyCodable(intervalMinutes),
            "grace_period_minutes": AnyCodable(gracePeriodMinutes),
            "status": AnyCodable("active"),
            "next_prompt_at": AnyCodable(ISO8601DateFormatter().string(from: nextPrompt)),
            "last_confirmed_at": AnyCodable(ISO8601DateFormatter().string(from: confirmedAt)),
        ]
        _ = try await client
            .from("session_checkins")
            .upsert(row, onConflict: "session_id")
            .execute()
    }

    private func logSafetyEvent(
        sessionId: UUID,
        shareId: UUID?,
        userId: UUID,
        type: String,
        location: CLLocation?,
        message: String?
    ) async throws {
        var row: [String: AnyCodable] = [
            "session_id": AnyCodable(sessionId.uuidString),
            "share_id": AnyCodable(shareId?.uuidString as Any),
            "created_by": AnyCodable(userId.uuidString),
            "event_type": AnyCodable(type),
            "message": AnyCodable(message as Any),
        ]
        if let location {
            row["lat"] = AnyCodable(location.coordinate.latitude)
            row["lon"] = AnyCodable(location.coordinate.longitude)
        }
        _ = try await client
            .from("safety_events")
            .insert(row)
            .execute()
    }

    private func evaluateCheckInState(now: Date, location: CLLocation) async {
        guard let sessionId = activeSessionId,
              let userId = AuthManager.shared.user?.id,
              let minutes = checkInInterval.minutes else {
            return
        }

        if let graceDeadline,
           now >= graceDeadline,
           !outstandingMissedCheckInLogged,
           let lastPromptAt {
            outstandingMissedCheckInLogged = true
            pendingCheckIn = nil
            missedCheckInMessage = "Safety check-in missed at \(formattedTime(lastPromptAt)). Anyone with the Beacon link will now see an alert."
            do {
                try await logSafetyEvent(
                    sessionId: sessionId,
                    shareId: currentShare?.id,
                    userId: userId,
                    type: "missed_check_in",
                    location: location,
                    message: "Missed safety check-in"
                )
                try await upsertCheckIn(
                    sessionId: sessionId,
                    shareId: currentShare?.id,
                    userId: userId,
                    intervalMinutes: minutes,
                    confirmedAt: now
                )
                await rescheduleNotifications(for: sessionId, from: now.addingTimeInterval(TimeInterval(minutes * 60)))
            } catch {
                errorMessage = "Couldn't log missed safety check-in: \(error.localizedDescription)"
            }
            return
        }

        guard pendingCheckIn == nil || outstandingMissedCheckInLogged == false else { return }

        let dueDate = lastPromptAt?.addingTimeInterval(TimeInterval(minutes * 60))
        if let dueDate, now < dueDate {
            return
        }

        if pendingCheckIn == nil {
            let prompt = PendingSafetyCheckIn(
                dueAt: now,
                graceDeadline: now.addingTimeInterval(TimeInterval(gracePeriodMinutes * 60))
            )
            pendingCheckIn = prompt
            lastPromptAt = now
            graceDeadline = prompt.graceDeadline
            outstandingMissedCheckInLogged = false

            let update: [String: AnyCodable] = [
                "last_prompted_at": AnyCodable(ISO8601DateFormatter().string(from: now))
            ]
            _ = try? await client
                .from("session_checkins")
                .update(update)
                .eq("session_id", value: sessionId.uuidString)
                .execute()
        }
    }

    private func autoEnablePreparedSetupIfNeeded() async {
        if currentShare != nil {
            preparedSetup = nil
            return
        }
        guard let preparedSetup else { return }

        await createOrRefreshShareLink()
        if currentShare != nil, preparedSetup.checkInInterval != .off {
            await updateCheckInInterval(preparedSetup.checkInInterval)
        }
        if currentShare != nil {
            self.preparedSetup = nil
        }
    }

    func composedShareMessage(for url: URL) -> String {
        let trimmed = shareMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseMessage = trimmed.isEmpty ? Self.defaultShareMessage : trimmed
        return "\(baseMessage)\n\n\(url.absoluteString)"
    }

    private func randomToken() -> String {
        let left = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let right = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "\(left)\(right)"
    }

    private func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02hhx", $0) }.joined()
    }

    private func makeShareURL(token: String) -> URL? {
        URL(string: "\(beaconBaseURL)/beacon/\(token)")
    }

    private func normalizedViewerLabel(from override: String?) -> String? {
        let trimmedOverride = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedOverride, !trimmedOverride.isEmpty {
            return trimmedOverride
        }

        guard !selectedRecipients.isEmpty else { return nil }
        if selectedRecipients.count == 1 {
            return selectedRecipients[0].name
        }
        if selectedRecipients.count == 2 {
            return "\(selectedRecipients[0].name), \(selectedRecipients[1].name)"
        }
        return "\(selectedRecipients[0].name), \(selectedRecipients[1].name), +\(selectedRecipients.count - 2) more"
    }

    private var batteryLevel: Double? {
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Double(level) : nil
    }

    private func resolvedMovementState(for location: CLLocation, isPaused: Bool) -> String {
        if isPaused {
            return "paused"
        }
        if location.speed >= 0.5 {
            return "moving"
        }
        if let lastHeartbeatLocation, lastHeartbeatLocation.distance(from: location) >= 8 {
            return "moving"
        }
        return "stationary"
    }

    private func requestNotificationPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        if !granted {
            throw NSError(domain: "SessionSafetyBeaconService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Notification permission is required for safety check-ins."
            ])
        }
    }

    private func rescheduleNotifications(for sessionId: UUID, from nextPromptAt: Date?) async {
        cancelNotifications(for: sessionId)
        guard let nextPromptAt else { return }

        let center = UNUserNotificationCenter.current()
        let promptRequest = UNNotificationRequest(
            identifier: promptNotificationId(for: sessionId),
            content: notificationContent(
                title: "Safety check-in",
                body: "Still good? Open FLYR and confirm your Beacon check-in."
            ),
            trigger: dateTrigger(for: nextPromptAt)
        )
        let graceRequest = UNNotificationRequest(
            identifier: graceNotificationId(for: sessionId),
            content: notificationContent(
                title: "Beacon still waiting",
                body: "Your safety check-in is overdue. Open FLYR to confirm you're okay."
            ),
            trigger: dateTrigger(for: nextPromptAt.addingTimeInterval(TimeInterval(gracePeriodMinutes * 60)))
        )
        try? await center.add(promptRequest)
        try? await center.add(graceRequest)
    }

    private func cancelNotifications(for sessionId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            promptNotificationId(for: sessionId),
            graceNotificationId(for: sessionId),
        ])
    }

    private func promptNotificationId(for sessionId: UUID) -> String {
        "flyr.beacon.prompt.\(sessionId.uuidString)"
    }

    private func graceNotificationId(for sessionId: UUID) -> String {
        "flyr.beacon.grace.\(sessionId.uuidString)"
    }

    private func notificationContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }

    private func dateTrigger(for date: Date) -> UNTimeIntervalNotificationTrigger {
        let interval = max(1, date.timeIntervalSinceNow)
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private extension PostgrestResponse {
    func decoded<U: Decodable>(decoder: JSONDecoder) throws -> U {
        try decoder.decode(U.self, from: data)
    }
}
