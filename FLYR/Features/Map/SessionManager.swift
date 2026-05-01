import Foundation
import CoreLocation
import Combine
import Supabase
import UIKit

enum SessionMode: String, Codable {
    case doorKnocking = "door_knocking"
    case flyer = "flyer"

    var defaultGoalType: GoalType {
        switch self {
        case .doorKnocking:
            return .knocks
        case .flyer:
            return .time
        }
    }

    var displayName: String {
        switch self {
        case .doorKnocking:
            return "Door Knocking"
        case .flyer:
            return "Flyer Route"
        }
    }
}

enum SessionVisitCompletionSource: String, Sendable {
    case manual
    case scored
    case legacyDwell
    case streetCoverage
}

// #region agent log
#if DEBUG
private let _debugLogDoorsQueue = DispatchQueue(label: "com.flyr.debuglog", qos: .background)
// TODO: Remove once hypothesis H1-H5 are resolved.
private func _debugLogDoors(location: String, message: String, data: [String: Any], hypothesisId: String) {
    let payload: [String: Any] = [
        "id": "log_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))",
        "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        "location": location,
        "message": message,
        "data": data,
        "hypothesisId": hypothesisId
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: json, encoding: .utf8) else { return }
    let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let path = baseURL.appendingPathComponent("flyr_debug.log").path
    let lineWithNewline = line + "\n"
    guard let dataToWrite = lineWithNewline.data(using: .utf8) else { return }
    let fileURL = URL(fileURLWithPath: path)
    _debugLogDoorsQueue.async {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber,
           size.int64Value > 10 * 1024 * 1024 {
            try? Data().write(to: fileURL, options: .atomic)
        }
        if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(dataToWrite)
            try? handle.close()
        } else {
            try? dataToWrite.write(to: fileURL, options: .atomic)
        }
    }
}
#else
private func _debugLogDoors(location: String, message: String, data: [String: Any], hypothesisId: String) {}
#endif
// #endregion

@MainActor
class SessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum SessionStartPhase: String {
        case createSession = "session_start.create_session"
        case loadRoads = "session_start.load_roads"
        case eventLog = "session_start.event_log"
    }

    enum SessionStartError: LocalizedError {
        case startAlreadyInFlight(campaignId: UUID)
        case campaignNotProvisioned(campaignId: UUID, reason: String)
        case phaseFailure(phase: SessionStartPhase, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .startAlreadyInFlight:
                return "A session start request is already in progress."
            case let .campaignNotProvisioned(_, reason):
                return reason
            case let .phaseFailure(phase, underlying):
                return "\(phase.rawValue) failed: \(underlying.localizedDescription)"
            }
        }
    }

    static let shared = SessionManager()
    /// Snapshot for end-session summary (building session); consumed by MapView then cleared.
    static var lastEndedSummary: SessionSummaryData?
    static var lastEndedSessionId: UUID?
    static var lastEndedSummaryMapSnapshot: UIImage?

    /// Set when a session ends so the UI can show the summary sheet. Observed by RecordHomeView.
    @Published var pendingSessionSummary: SessionSummaryData?
    @Published var pendingSessionSummarySessionId: UUID?

    @Published var isActive = false
    @Published var pathCoordinates: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var startTime: Date?
    @Published var elapsedTime: TimeInterval = 0
    @Published var goalType: GoalType = .knocks
    @Published var sessionMode: SessionMode = .doorKnocking
    @Published var goalAmount: Int = 0
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLLocationDirection = 0
    @Published private(set) var headingState: MapHeadingState = .unavailable
    @Published private(set) var headingPresentationState: MapHeadingPresentationState = .unavailable
    @Published var flyersDelivered: Int = 0
    @Published var conversationsHad: Int = 0
    @Published var leadsCreated: Int = 0
    @Published var appointmentsSet: Int = 0

    // Route-based session properties
    @Published var optimizedRoute: OptimizedRoute?
    @Published var currentWaypointIndex: Int = 0
    @Published var completedWaypoints: Set<UUID> = []
    @Published var campaignId: UUID?
    /// Notes for the current session (set at start, saved to Supabase)
    @Published var sessionNotes: String?
    /// Set when the session was started from a workspace route assignment (stored on `sessions.route_assignment_id`).
    @Published private(set) var routeAssignmentId: UUID?
    @Published private(set) var isDemoSession = false
    @Published private(set) var currentFarmExecutionContext: FarmExecutionContext?

    // MARK: - Building session (session recording)
    /// When true, tab bar stays visible so user can navigate after app open (session was restored, not started this launch).
    @Published var sessionRestoredThisLaunch = false
    /// Active session was restored and is older than `staleActiveSessionThreshold`; GPS/timer were not started until the user chooses Resume or End & Save.
    @Published var staleActiveSessionNeedsResolution = false
    /// Wall-clock age after which a restored open session prompts for resume vs end (6 hours).
    static let staleActiveSessionThreshold: TimeInterval = 6 * 3600
    @Published var sessionId: UUID?
    @Published private(set) var activeSharedLiveSessionId: UUID?
    @Published var targetBuildings: [String] = [] // gers_ids
    @Published var completedBuildings: Set<String> = []
    @Published private(set) var pendingVisitedTargets: Set<String> = []
    @Published private(set) var confirmedVisitedTargets: Set<String> = []
    @Published private(set) var pendingVisitedAddressIds: Set<String> = []
    @Published private(set) var confirmedVisitedAddressIds: Set<String> = []
    @Published private(set) var pendingVisitedBuildingIds: Set<String> = []
    @Published private(set) var confirmedVisitedBuildingIds: Set<String> = []
    @Published private(set) var failedVisitedTargets: [String: String] = [:]
    @Published private(set) var visitOverlayRevision: Int = 0
    @Published var autoCompleteEnabled = false
    @Published var isPaused = false
    @Published var showLongSessionPrompt = false
    @Published var sessionEndError: String?
    /// GPS/location error state for UI (e.g. "Searching for GPS...", "Location denied")
    @Published var locationError: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published var showBackgroundLocationUpgradePrompt = false

    /// Centroids for auto-complete: gers_id -> location. Set when starting building session.
    var buildingCentroids: [String: CLLocation] = [:]

    /// Count of addresses user marked as delivered (knocked) this session via the location card. Used for summary "doors" when no building targets.
    @Published var addressesMarkedDelivered: Int = 0
    private var trackedVisitedAddressIds: Set<String> = []
    private var anonymousDoorHitCount = 0

    /// GPS samples when anonymous doors are recorded so the share card can plot pins even when
    /// we do not have a reversible address/target key to attach to the hit.
    private var shareCardDoorPinCoordinates: [CLLocationCoordinate2D] = []
    private var shareCardDoorPinsByTargetId: [String: CLLocationCoordinate2D] = [:]
    private var shareCardDoorPinsByAddressId: [String: CLLocationCoordinate2D] = [:]

    var targetCount: Int { targetBuildings.count }
    /// When restored from server without event replay, use server value; else use local set count
    private var serverCompletedCount: Int?
    var completedCount: Int { serverCompletedCount ?? confirmedVisitedTargets.count }
    var remainingCount: Int { max(0, targetCount - completedCount) }
    var progressPercentage: Double {
        targetCount > 0 ? Double(completedCount) / Double(targetCount) : 0
    }
    /// Keep the leaderboard's session metric in sync with door-knocking progress even when
    /// the flow only updates completed/visited counts during the active session.
    private var leaderboardFlyersDelivered: Int {
        if sessionMode == .doorKnocking {
            return effectiveDoorKnockCount
        }
        return flyersDelivered
    }

    private var effectiveDoorKnockCount: Int {
        guard sessionMode == .doorKnocking else { return 0 }
        if targetCount > 0 {
            return completedCount
        }
        return max(addressesMarkedDelivered, 0)
    }

    var autoCompleteThresholdMeters: Double = 10.0
    var autoCompleteDwellSeconds: Double = 5.0
    var autoCompleteMaxSpeedMPS: Double = 1.8
    var autoCompleteRequiredAccuracyMeters: Double = 10.0
    private var dwellTracker: [String: DwellState] = [:]
    private var lastAutoCompleteTime: Date?
    private let autoCompleteDebounceSeconds: Double = 3.0

    private var timer: Timer?
    private var locationManager = CLLocationManager()
    private let headingManager = MapHeadingManager.shared
    private let sessionRepository = SessionRepository.shared
    private let outboxRepository = OutboxRepository.shared
    private var headingSubscriptions = Set<AnyCancellable>()
    private var lastLocation: CLLocation?
    private let minPathMovementMeters: Double = 3.0
    private let maxHorizontalAccuracy: Double = 15.0
    private let minSpeed: Double = 0.2
    private let stationarySpeedThreshold: Double = 0.4
    private let stationaryMovementMeters: Double = 8.0
    /// Scale factor for GPS uncertainty when user appears stationary.
    private let stationaryAccuracyMultiplier: Double = 0.9
    /// Require a minimum implied speed before accepting "stationary" movement to suppress slow drift.
    private let stationaryMinImpliedSpeedMPS: Double = 0.55
    private let maxTimeGapSeconds: Double = 15.0
    private let maxTimeGapDistanceMeters: Double = 30.0
    private lazy var sessionGPSFilter = SessionGPSFilter(
        minPathMovementMeters: minPathMovementMeters,
        maxHorizontalAccuracy: maxHorizontalAccuracy,
        minSpeed: minSpeed,
        stationarySpeedThreshold: stationarySpeedThreshold,
        stationaryMovementMeters: stationaryMovementMeters,
        stationaryAccuracyMultiplier: stationaryAccuracyMultiplier,
        stationaryMinImpliedSpeedMPS: stationaryMinImpliedSpeedMPS,
        maxImpliedSpeedMPS: 10.0
    )
    private var segmentBreaks: Set<Int> = []
    private var lastSimplifiedCount: Int = 0
    private var cachedSimplifiedPath: [[CLLocationCoordinate2D]] = []
    private var proNormalizationConfig: GPSNormalizationConfig = .default
    private var trailNormalizer: SessionTrailNormalizer?
    /// Visit inference from accepted raw + corridor context only. Never uses the rendered path.
    private var scoredVisitEngine: ScoredVisitEngine?
    /// Street-level path coverage fallback from accepted raw points + corridor context only.
    private var streetCoverageVisitEngine: StreetCoverageVisitEngine?
    /// Server `is_paused` before forcing pause for stale-session UX; reapplied when user taps Resume.
    private var restoredServerPausedAfterStalePrompt: Bool = false
    /// When true and engine is available, use scored visit inference instead of legacy dwell-based auto-complete.
    private var useScoredVisitEngine: Bool = true
    /// Flyer mode: targets and centroids for scored engine. Set by FlyerModeManager so visit outcomes use accepted raw + corridor (never display path).
    private var flyerTargetIds: [String] = []
    private var flyerCentroids: [String: CLLocation] = [:]
    /// Called when scored engine marks flyer addresses visited. Consumer updates UI and VisitsAPI.
    var onFlyerAddressesCompleted: (([String]) -> Void)?
    /// Road corridors for the current session (Mapbox road segments). Used to draw the walking trail/road centerlines on the session map.
    @Published var sessionRoadCorridors: [StreetCorridor] = []
    private var acceptanceFilter: LocationAcceptanceFilter { LocationAcceptanceFilter(config: proNormalizationConfig) }
    private var conversationAddressIds: Set<UUID> = []
    private var appointmentAddressIds: Set<UUID> = []
    private let waypointReachedThresholdMeters: Double = 10.0
    private var activeSecondsAccumulator: TimeInterval = 0
    private var activeSegmentStartTime: Date?
    private var pauseStartTime: Date?
    private var pendingEventQueue: [PendingSessionEvent] = []
    private var targetAddressIdsByTargetId: [String: [UUID]] = [:]
    private var targetBuildingIdsByTargetId: [String: String] = [:]
    private var inFlightVisitConfirmationTasks: [String: Task<Void, Never>] = [:]
    private var progressSyncer = SessionProgressSyncer()
    private let liveActivityManager = SessionLiveActivityManager.shared
    private let safetyBeaconService = SessionSafetyBeaconService.shared
    private let sharedLiveCanvassingService = SharedLiveCanvassingService.shared
    private let headingPresentationEngine = MapHeadingPresentationEngine()
    private var lastLiveActivityPeriodicSync: Date?
    private var lastSharedLivePresencePeriodicSync: Date?
    private var hasShownLongSessionPrompt = false
    private var hasAutoEndedLongSession = false
    private var isEndingSession = false
    private var startInFlightCampaignId: UUID?
    private var endInFlightSessionId: UUID?
    private let longSessionPromptSeconds: TimeInterval = 3 * 60 * 60
    private let longSessionAutoEndSeconds: TimeInterval = 8 * 60 * 60
    private var hasShownBackgroundLocationUpgradePromptThisSession = false
    @Published private(set) var acceptedRawPointCount: Int = 0
    @Published private(set) var rejectedPointCounts: [RejectionReason: Int] = [:]
    @Published private(set) var scoredCompletionCount: Int = 0
    @Published private(set) var dwellCompletionCount: Int = 0
    @Published private(set) var streetCoverageCandidateCount: Int = 0
    @Published private(set) var pendingToConfirmedCount: Int = 0
    @Published private(set) var pendingToFailedCount: Int = 0
    @Published private(set) var sameSideMatchCount: Int = 0
    @Published private(set) var oppositeSideMatchCount: Int = 0
    @Published private(set) var matchedDistanceSampleCount: Int = 0
    @Published private(set) var matchedDistanceTotalMeters: Double = 0
    @Published private(set) var recentVisitDebugMessages: [String] = []
    @Published private(set) var recentRejectionEntries: [String] = []

    var isNetworkingSession: Bool {
        sessionId != nil && campaignId == nil && targetBuildings.isEmpty && goalType == .time && !isDemoSession
    }

    private override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 2.0
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = true
        }

        headingManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.headingState = state
                self.refreshHeadingPresentation(using: self.currentLocation, headingState: state)
            }
            .store(in: &headingSubscriptions)
    }

    private func refreshHeadingPresentation(
        using location: CLLocation?,
        headingState: MapHeadingState? = nil
    ) {
        let resolvedHeadingState = headingState ?? self.headingState
        let presentationState = headingPresentationEngine.nextState(
            location: location,
            headingState: resolvedHeadingState
        )
        self.headingPresentationState = presentationState
        self.currentHeading = presentationState.heading ?? 0
    }

    private func restoreFarmExecutionContext(from session: SessionRecord) async -> FarmExecutionContext? {
        guard let touchId = session.farm_touch_id else { return nil }

        do {
            guard let touch = try await FarmTouchService.shared.fetchTouch(id: touchId) else {
                return nil
            }

            if let resolved = try await FarmExecutionService.shared.executionContext(for: touch) {
                return resolved
            }

            guard let campaignId = touch.campaignId ?? session.campaign_id else { return nil }

            async let farm = FarmService.shared.fetchFarm(id: touch.farmId)
            let resolvedFarm = try await farm

            return FarmExecutionContext(
                farmId: touch.farmId,
                farmName: resolvedFarm?.name ?? "Farm",
                touchId: touch.id,
                touchTitle: touch.title,
                touchDate: touch.date,
                touchType: touch.type,
                campaignId: campaignId,
                cycleNumber: touch.cycleNumber,
                cycleName: touch.cycleNumber.map { "Cycle \($0)" }
            )
        } catch {
            print("⚠️ [SessionManager] Could not restore farm execution context: \(error)")
            return nil
        }
    }

    private func requestAuthorizationAndStartLocation(for mode: SessionMode) {
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationError = nil
            startLocationUpdatesIfAuthorized()
            presentBackgroundLocationUpgradePromptIfNeeded()
            return
        }
        if status == .denied || status == .restricted {
            locationError = "Location access denied"
        }
    }

    private func startLocationUpdatesIfAuthorized() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        locationManager.startUpdatingLocation()
        headingManager.start()
    }

    var locationAuthorizationStatus: CLAuthorizationStatus {
        authorizationStatus
    }

    var hasPersistentBackgroundLocationAccess: Bool {
        authorizationStatus == .authorizedAlways
    }

    func requestForegroundLocationAuthorization() {
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationError = nil
            startLocationUpdatesIfAuthorized()
        } else if status == .denied || status == .restricted {
            locationError = "Location access denied"
        }
    }

    func requestBackgroundLocationAuthorization() {
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        showBackgroundLocationUpgradePrompt = false
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        } else if status == .denied || status == .restricted {
            locationError = "Location access denied"
        }
    }

    func dismissBackgroundLocationUpgradePrompt() {
        showBackgroundLocationUpgradePrompt = false
        hasShownBackgroundLocationUpgradePromptThisSession = true
    }

    private func resetBackgroundLocationUpgradePromptState() {
        showBackgroundLocationUpgradePrompt = false
        hasShownBackgroundLocationUpgradePromptThisSession = false
    }

    private func presentBackgroundLocationUpgradePromptIfNeeded() {
        guard isActive,
              authorizationStatus == .authorizedWhenInUse,
              !hasPersistentBackgroundLocationAccess,
              !hasShownBackgroundLocationUpgradePromptThisSession else {
            if hasPersistentBackgroundLocationAccess {
                showBackgroundLocationUpgradePrompt = false
            }
            return
        }
        hasShownBackgroundLocationUpgradePromptThisSession = true
        showBackgroundLocationUpgradePrompt = true
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(handleElapsedTimerTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func currentActiveElapsedTime(referenceDate: Date = Date()) -> TimeInterval {
        guard let activeSegmentStartTime else { return activeSecondsAccumulator }
        return activeSecondsAccumulator + max(0, referenceDate.timeIntervalSince(activeSegmentStartTime))
    }

    @objc private func handleElapsedTimerTick() {
        guard startTime != nil else { return }
        if sessionId != nil && isPaused {
            elapsedTime = currentActiveElapsedTime(referenceDate: pauseStartTime ?? Date())
            return
        }
        elapsedTime = currentActiveElapsedTime()
        evaluateLongRunningSession()

        // Periodic refresh of Live Activity so lock screen widget timer stays correct
        let now = Date()
        if sessionId != nil,
           lastLiveActivityPeriodicSync.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            lastLiveActivityPeriodicSync = now
            Task { await syncLiveActivity(forceStart: false) }
        }

        if sessionId != nil,
           sharedLiveCanvassingService.isJoined,
           lastSharedLivePresencePeriodicSync.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            lastSharedLivePresencePeriodicSync = now
            let location = currentLocation
            let paused = isPaused
            Task {
                await sharedLiveCanvassingService.publishPresence(
                    location: location,
                    isPaused: paused,
                    force: true
                )
            }
        }
    }

    private func evaluateLongRunningSession() {
        guard sessionId != nil, isActive else { return }

        if elapsedTime >= longSessionPromptSeconds, !hasShownLongSessionPrompt {
            hasShownLongSessionPrompt = true
            showLongSessionPrompt = true
        }

        if elapsedTime >= longSessionAutoEndSeconds, !hasAutoEndedLongSession {
            hasAutoEndedLongSession = true
            showLongSessionPrompt = false
            print("⏱️ [SessionManager] Auto-ending long-running session after \(Int(elapsedTime))s")
            Task { await stopBuildingSession() }
        }
    }

    // MARK: - Session State Reset Helpers

    private func resetSessionState() {
        startTime = Date()
        pathCoordinates = []
        distanceMeters = 0
        elapsedTime = 0
        currentHeading = 0
        headingState = .unavailable
        headingPresentationState = .unavailable
        headingPresentationEngine.reset()
        headingManager.stop(reset: true)
        lastLocation = nil
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        optimizedRoute = nil
        currentWaypointIndex = 0
        completedWaypoints = []
        campaignId = nil
        flyersDelivered = 0
        conversationsHad = 0
        leadsCreated = 0
        appointmentsSet = 0
        appointmentAddressIds = []
        isDemoSession = false
        progressSyncer.reset()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false
        resetBackgroundLocationUpgradePromptState()
        resetBackgroundLocationUpgradePromptState()
        activeSecondsAccumulator = 0
        activeSegmentStartTime = nil
        pauseStartTime = nil
        resetVisitState()
    }

    private func normalizeVisitKey(_ targetId: String) -> String {
        targetId.lowercased()
    }

    private func normalizeBuildingKey(_ buildingId: String?) -> String? {
        buildingId?.lowercased()
    }

    private func normalizeAddressKey(_ addressId: UUID) -> String {
        addressId.uuidString.lowercased()
    }

    private func effectiveVisitedTargets() -> Set<String> {
        completedBuildings
    }

    private func refreshCompletedBuildingSnapshot() {
        completedBuildings = pendingVisitedTargets.union(confirmedVisitedTargets)
        visitOverlayRevision &+= 1
    }

    private func resetVisitState() {
        completedBuildings = []
        pendingVisitedTargets = []
        confirmedVisitedTargets = []
        pendingVisitedAddressIds = []
        confirmedVisitedAddressIds = []
        pendingVisitedBuildingIds = []
        confirmedVisitedBuildingIds = []
        failedVisitedTargets = [:]
        targetAddressIdsByTargetId = [:]
        targetBuildingIdsByTargetId = [:]
        acceptedRawPointCount = 0
        rejectedPointCounts = [:]
        scoredCompletionCount = 0
        dwellCompletionCount = 0
        streetCoverageCandidateCount = 0
        pendingToConfirmedCount = 0
        pendingToFailedCount = 0
        sameSideMatchCount = 0
        oppositeSideMatchCount = 0
        matchedDistanceSampleCount = 0
        matchedDistanceTotalMeters = 0
        recentVisitDebugMessages = []
        recentRejectionEntries = []
        trackedVisitedAddressIds = []
        anonymousDoorHitCount = 0
        addressesMarkedDelivered = 0
        shareCardDoorPinCoordinates = []
        shareCardDoorPinsByTargetId = [:]
        shareCardDoorPinsByAddressId = [:]
        visitOverlayRevision = 0
        inFlightVisitConfirmationTasks.values.forEach { $0.cancel() }
        inFlightVisitConfirmationTasks.removeAll()
    }

    private func appendVisitDebugMessage(_ message: String) {
        recentVisitDebugMessages.insert(message, at: 0)
        if recentVisitDebugMessages.count > 20 {
            recentVisitDebugMessages.removeLast(recentVisitDebugMessages.count - 20)
        }
        #if DEBUG
        print(message)
        #endif
    }

    private func recordAcceptedRawPoint() {
        acceptedRawPointCount += 1
    }

    private func buildOfflineSessionPayload(
        sessionId: UUID,
        userId: UUID,
        campaignId: UUID,
        targetBuildings: [String],
        autoCompleteEnabled: Bool,
        notes: String?,
        goalType: GoalType,
        goalAmount: Int,
        mode: SessionMode,
        routeAssignmentId: UUID?,
        farmExecutionContext: FarmExecutionContext?,
        startedAt: Date
    ) -> OfflineSessionPayload {
        OfflineSessionPayload(
            id: sessionId.uuidString,
            userId: userId.uuidString,
            campaignId: campaignId.uuidString,
            targetBuildings: targetBuildings,
            autoCompleteEnabled: autoCompleteEnabled,
            thresholdMeters: autoCompleteThresholdMeters,
            dwellSeconds: Int(autoCompleteDwellSeconds),
            notes: notes,
            workspaceId: WorkspaceContext.shared.workspaceId?.uuidString,
            goalType: goalType.rawValue,
            goalAmount: goalAmount,
            sessionMode: mode.rawValue,
            routeAssignmentId: routeAssignmentId?.uuidString,
            farmExecutionContext: farmExecutionContext.map(OfflineFarmExecutionPayload.init(context:)),
            startedAt: OfflineDateCodec.string(from: startedAt)
        )
    }

    private func makeSessionProgressPayload(
        sessionId: UUID,
        activeSeconds: Int,
        pathGeoJSONNormalized: String? = nil,
        endTime: Date? = nil
    ) -> SessionProgressOutboxPayload {
        SessionProgressOutboxPayload(
            id: sessionId.uuidString,
            campaignId: campaignId?.uuidString,
            completedCount: completedCount,
            distanceM: distanceMeters,
            activeSeconds: activeSeconds,
            pathGeoJSON: coordinatesToGeoJSON(pathCoordinates),
            pathGeoJSONNormalized: pathGeoJSONNormalized,
            flyersDelivered: leaderboardFlyersDelivered,
            conversations: conversationsHad,
            leadsCreated: leadsCreated,
            appointmentsCount: appointmentsSet,
            doorsHit: effectiveDoorKnockCount,
            autoCompleteEnabled: autoCompleteEnabled,
            isPaused: isPaused,
            endTime: endTime.map(OfflineDateCodec.string(from:))
        )
    }

    private func enqueueSessionProgressOutbox(
        sessionId: UUID,
        activeSeconds: Int,
        operation: OutboxOperation = .updateSessionProgress,
        pathGeoJSONNormalized: String? = nil,
        endTime: Date? = nil
    ) async {
        let payload = makeSessionProgressPayload(
            sessionId: sessionId,
            activeSeconds: activeSeconds,
            pathGeoJSONNormalized: pathGeoJSONNormalized,
            endTime: endTime
        )
        await outboxRepository.enqueue(
            entityType: "session",
            entityId: sessionId.uuidString,
            operation: operation,
            payload: payload,
            dependencyKey: "session:\(sessionId.uuidString.lowercased())"
        )
        if NetworkMonitor.shared.isOnline {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
    }

    private func enqueueSessionEvent(
        sessionId: UUID,
        campaignId: UUID,
        buildingId: String?,
        eventType: SessionEventType,
        location: CLLocation?,
        metadata: [String: String] = [:],
        occurredAt: Date = Date()
    ) async {
        let payload = SessionEventOutboxPayload(
            localEventId: UUID().uuidString,
            sessionId: sessionId.uuidString,
            campaignId: campaignId.uuidString,
            buildingId: buildingId,
            eventType: eventType.rawValue,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            metadata: metadata
        )
        _ = await sessionRepository.addLocalSessionEvent(
            id: UUID(uuidString: payload.localEventId) ?? UUID(),
            sessionId: sessionId,
            campaignId: campaignId,
            entityType: "session_event",
            entityId: buildingId,
            eventType: eventType.rawValue,
            payloadJSON: OfflineJSONCodec.encode(payload),
            occurredAt: occurredAt
        )
        await outboxRepository.enqueue(
            entityType: "session_event",
            entityId: payload.localEventId,
            operation: .createSessionEvent,
            payload: payload,
            dependencyKey: "session:\(sessionId.uuidString.lowercased())"
        )
        if NetworkMonitor.shared.isOnline {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
    }

    private func persistLocalActiveSessionSnapshot(pathGeoJSONNormalized: String? = nil) async {
        guard let sessionId else { return }
        await sessionRepository.updateSessionProgress(
            id: sessionId,
            distanceMeters: distanceMeters,
            pathGeoJSON: coordinatesToGeoJSON(pathCoordinates),
            pathGeoJSONNormalized: pathGeoJSONNormalized,
            status: isPaused ? "paused" : "active"
        )
    }

    private func restoreLocalSession(_ snapshot: LocalSessionSnapshot) async {
        sessionId = snapshot.id
        campaignId = snapshot.campaignId
        targetBuildings = snapshot.payload?.targetBuildings ?? []
        routeAssignmentId = snapshot.payload?.routeAssignmentId.flatMap(UUID.init(uuidString:))
        currentFarmExecutionContext = snapshot.payload?.farmExecutionContext?.makeContext()
        resetVisitState()

        var completed = Set<String>()
        for event in snapshot.events.sorted(by: { $0.occurredAt < $1.occurredAt }) {
            guard let entityId = event.entityId?.lowercased() else { continue }
            switch event.eventType {
            case SessionEventType.completionUndone.rawValue:
                completed.remove(entityId)
            case SessionEventType.completedManual.rawValue,
                 SessionEventType.completedAuto.rawValue,
                 SessionEventType.flyerLeft.rawValue,
                 SessionEventType.conversation.rawValue:
                completed.insert(entityId)
            default:
                break
            }
        }
        confirmedVisitedTargets = completed
        refreshCompletedBuildingSnapshot()
        serverCompletedCount = nil
        startTime = snapshot.startedAt
        pathCoordinates = snapshot.points.filter(\.accepted).map(\.coordinate)
        distanceMeters = snapshot.distanceMeters
        lastLocation = nil
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        elapsedTime = Date().timeIntervalSince(snapshot.startedAt)
        activeSecondsAccumulator = elapsedTime
        sessionRestoredThisLaunch = true
        isActive = true
        staleActiveSessionNeedsResolution = true
        restoredServerPausedAfterStalePrompt = snapshot.status == "paused"
        autoCompleteEnabled = snapshot.payload?.autoCompleteEnabled ?? false
        flyersDelivered = 0
        conversationsHad = 0
        leadsCreated = 0
        appointmentsSet = 0
        appointmentAddressIds = []
        goalType = snapshot.payload.flatMap { GoalType(rawValue: $0.goalType) } ?? .knocks
        goalAmount = max(0, snapshot.payload?.goalAmount ?? 0)
        sessionMode = snapshot.mode
        isPaused = true
        activeSegmentStartTime = nil
        progressSyncer.setBaseline(
            pathCount: pathCoordinates.count,
            distanceMeters: distanceMeters,
            activeSeconds: Int(elapsedTime),
            completedCount: completedCount,
            conversations: conversationsHad,
            leadsCreated: leadsCreated,
            at: Date()
        )
        buildingCentroids = [:]
        resetBackgroundLocationUpgradePromptState()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false
        print("⏸️ [SessionManager] Restored local session \(snapshot.id) — awaiting resume or end")
    }

    private func recordRejectedPoint(_ reason: RejectionReason, location: CLLocation?) {
        rejectedPointCounts[reason, default: 0] += 1
        let entry: String
        if let location {
            entry = "\(reason.rawValue) @ \(String(format: "%.5f", location.coordinate.latitude)),\(String(format: "%.5f", location.coordinate.longitude))"
        } else {
            entry = reason.rawValue
        }
        recentRejectionEntries.insert(entry, at: 0)
        if recentRejectionEntries.count > 12 {
            recentRejectionEntries.removeLast(recentRejectionEntries.count - 12)
        }
    }

    private func recordMatchedDistance(_ distanceMeters: Double) {
        matchedDistanceSampleCount += 1
        matchedDistanceTotalMeters += distanceMeters
    }

    private func updatePendingVisitState(
        targetId: String,
        addressIds: [UUID],
        buildingId: String?,
        haptic: Bool
    ) -> Bool {
        let targetKey = normalizeVisitKey(targetId)
        guard !completedBuildings.contains(targetKey) else { return false }
        pendingVisitedTargets.insert(targetKey)
        failedVisitedTargets.removeValue(forKey: targetKey)
        addressIds.forEach { pendingVisitedAddressIds.insert(normalizeAddressKey($0)) }
        if let buildingKey = normalizeBuildingKey(buildingId) {
            pendingVisitedBuildingIds.insert(buildingKey)
        }
        refreshCompletedBuildingSnapshot()
        if haptic {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        return true
    }

    @discardableResult
    private func confirmVisitState(
        targetId: String,
        addressIds: [UUID],
        buildingId: String?,
        haptic: Bool = false
    ) async -> Bool {
        let targetKey = normalizeVisitKey(targetId)
        let wasPending = pendingVisitedTargets.remove(targetKey) != nil
        let insertedConfirmed = confirmedVisitedTargets.insert(targetKey).inserted
        addressIds.forEach {
            let key = normalizeAddressKey($0)
            pendingVisitedAddressIds.remove(key)
            confirmedVisitedAddressIds.insert(key)
        }
        if let buildingKey = normalizeBuildingKey(buildingId) {
            pendingVisitedBuildingIds.remove(buildingKey)
            confirmedVisitedBuildingIds.insert(buildingKey)
        }
        failedVisitedTargets.removeValue(forKey: targetKey)
        serverCompletedCount = nil
        refreshCompletedBuildingSnapshot()
        await syncLiveActivity(forceStart: false)
        if wasPending {
            pendingToConfirmedCount += 1
        }
        if haptic {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        return insertedConfirmed || wasPending
    }

    private func revertPendingVisitState(
        targetId: String,
        addressIds: [UUID],
        buildingId: String?,
        reason: String
    ) {
        let targetKey = normalizeVisitKey(targetId)
        guard pendingVisitedTargets.remove(targetKey) != nil else { return }
        addressIds.forEach { pendingVisitedAddressIds.remove(normalizeAddressKey($0)) }
        if let buildingKey = normalizeBuildingKey(buildingId) {
            pendingVisitedBuildingIds.remove(buildingKey)
        }
        failedVisitedTargets[targetKey] = reason
        pendingToFailedCount += 1
        refreshCompletedBuildingSnapshot()
    }

    func configureSessionTargetMappings(
        addressIdsByTargetId: [String: [UUID]],
        buildingIdsByTargetId: [String: String]
    ) {
        targetAddressIdsByTargetId = addressIdsByTargetId.reduce(into: [String: [UUID]]()) { result, entry in
            let key = normalizeVisitKey(entry.key)
            let normalizedIds = Array(Set(entry.value))
            result[key] = Array(Set((result[key] ?? []) + normalizedIds))
        }
        targetBuildingIdsByTargetId = buildingIdsByTargetId.reduce(into: [String: String]()) { result, entry in
            let key = normalizeVisitKey(entry.key)
            result[key] = result[key] ?? entry.value
        }
    }

    private func resolvedAddressIds(for targetId: String) -> [UUID] {
        targetAddressIdsByTargetId[normalizeVisitKey(targetId)] ?? []
    }

    private func resolvedBuildingId(for targetId: String, addressIds: [UUID]) -> String? {
        if let buildingId = targetBuildingIdsByTargetId[normalizeVisitKey(targetId)], !buildingId.isEmpty {
            return buildingId
        }
        return UUID(uuidString: targetId) == nil ? targetId : nil
    }

    func resolvedSessionTargetId(forAddressId addressId: UUID, buildingId: String? = nil) -> String? {
        let addressKey = normalizeAddressKey(addressId)
        if targetAddressIdsByTargetId[addressKey] != nil || targetBuildingIdsByTargetId[addressKey] != nil {
            return addressKey
        }

        let matchingTargets = targetAddressIdsByTargetId.compactMap { targetId, addressIds in
            addressIds.contains(addressId) ? targetId : nil
        }

        if matchingTargets.count == 1 {
            return matchingTargets[0]
        }

        if let buildingKey = normalizeBuildingKey(buildingId) {
            if targetAddressIdsByTargetId[buildingKey] != nil || targetBuildingIdsByTargetId[buildingKey] != nil {
                return buildingKey
            }

            if let buildingMatch = matchingTargets.first(where: { targetId in
                normalizeBuildingKey(targetBuildingIdsByTargetId[targetId]) == buildingKey || targetId == buildingKey
            }) {
                return buildingMatch
            }
        }

        return matchingTargets.first
    }

    private func awaitInFlightVisitConfirmations() async {
        let tasks = Array(inFlightVisitConfirmationTasks.values)
        for task in tasks {
            await task.value
        }
    }

    func start(goalType: GoalType, goalAmount: Int) {
        self.goalType = goalType
        self.sessionMode = (goalType == .flyers) ? .flyer : .doorKnocking
        self.goalAmount = goalAmount
        resetSessionState()

        isActive = true

        requestAuthorizationAndStartLocation(for: self.sessionMode)

        // Start timer for elapsed time
        activeSecondsAccumulator = 0
        activeSegmentStartTime = Date()
        startElapsedTimer()
        Task { await syncLiveActivity(forceStart: true) }
    }

    /// Start a route-based session with optimized waypoints
    func start(goalType: GoalType, goalAmount: Int? = nil, route: OptimizedRoute, campaignId: UUID?) {
        self.goalType = goalType
        self.sessionMode = (goalType == .flyers) ? .flyer : .doorKnocking
        self.goalAmount = goalAmount ?? route.stopCount
        resetSessionState()
        self.optimizedRoute = route
        self.campaignId = campaignId

        isActive = true

        requestAuthorizationAndStartLocation(for: self.sessionMode)

        // Start timer for elapsed time
        startElapsedTimer()
        Task { await syncLiveActivity(forceStart: true) }

        print("✅ [SessionManager] Started route-based session with \(route.stopCount) waypoints")
    }

    func startDemoBuildingSession(
        campaignId: UUID,
        targetBuildings: [String],
        centroids: [String: CLLocationCoordinate2D] = [:],
        mode: SessionMode = .doorKnocking,
        initialLocation: CLLocationCoordinate2D? = nil
    ) {
        sessionRestoredThisLaunch = false
        sessionId = UUID()
        SessionManager.lastEndedSummaryMapSnapshot = nil
        self.campaignId = campaignId
        routeAssignmentId = nil
        self.targetBuildings = targetBuildings
        resetVisitState()
        serverCompletedCount = nil
        autoCompleteEnabled = false
        sessionNotes = nil
        sessionMode = mode
        sessionEndError = nil
        isDemoSession = true
        buildingCentroids = centroids.mapValues { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        dwellTracker = [:]
        lastAutoCompleteTime = nil
        startTime = Date()
        pathCoordinates = []
        distanceMeters = 0
        elapsedTime = 0
        let startingLocation = initialLocation.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        currentLocation = startingLocation
        lastLocation = startingLocation
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        progressSyncer.reset()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false
        resetBackgroundLocationUpgradePromptState()
        activeSecondsAccumulator = 0
        activeSegmentStartTime = Date()
        isPaused = false
        optimizedRoute = nil
        goalType = mode.defaultGoalType
        goalAmount = goalType.defaultAmount(for: mode, targetCount: targetBuildings.count)
        addressesMarkedDelivered = 0
        shareCardDoorPinCoordinates = []
        appointmentsSet = 0
        appointmentAddressIds = []
        locationError = nil
        trailNormalizer = nil
        scoredVisitEngine = nil
        streetCoverageVisitEngine = nil
        flyerTargetIds = []
        flyerCentroids = [:]
        onFlyerAddressesCompleted = nil
        sessionRoadCorridors = []
        startElapsedTimer()
        isActive = true
    }

    func injectDemoLocation(
        _ coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        appendToTrail: Bool = true
    ) async {
        guard isDemoSession, sessionId != nil else { return }

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: 0.8,
            timestamp: timestamp
        )
        let addedDistance = appendToTrail ? (lastLocation.map { location.distance(from: $0) } ?? 0) : 0
        lastLocation = location
        currentLocation = location
        if appendToTrail {
            pathCoordinates.append(coordinate)
        } else if !pathCoordinates.isEmpty {
            segmentBreaks.insert(pathCoordinates.count)
            cachedSimplifiedPath = []
            lastSimplifiedCount = 0
        }
        distanceMeters += addedDistance
        await syncLiveActivity(forceStart: false)
    }

    /// Start a standalone networking session with no campaign context.
    func startNetworkingSession(notes: String? = nil) async throws {
        sessionRestoredThisLaunch = false
        guard let userId = AuthManager.shared.user?.id else {
            print("⚠️ [SessionManager] Cannot start networking session: not authenticated")
            return
        }
        if startInFlightCampaignId != nil {
            throw SessionStartError.startAlreadyInFlight(campaignId: campaignId ?? UUID())
        }

        startInFlightCampaignId = UUID()
        defer { startInFlightCampaignId = nil }

        let newSessionId = UUID()
        let sessionStartedAt = Date()
        let resolvedGoalType: GoalType = .time
        let resolvedGoalAmount = resolvedGoalType.defaultAmount(for: .doorKnocking, targetCount: 0)

        do {
            try await SessionsAPI.shared.createSession(
                id: newSessionId,
                userId: userId,
                campaignId: nil,
                targetBuildingIds: [],
                autoCompleteEnabled: false,
                thresholdMeters: autoCompleteThresholdMeters,
                dwellSeconds: Int(autoCompleteDwellSeconds),
                notes: notes,
                workspaceId: WorkspaceContext.shared.workspaceId,
                goalType: resolvedGoalType,
                goalAmount: resolvedGoalAmount,
                sessionMode: .doorKnocking,
                startedAt: sessionStartedAt
            )
        } catch {
            throw SessionStartError.phaseFailure(phase: .createSession, underlying: error)
        }

        sessionId = newSessionId
        SessionManager.lastEndedSummaryMapSnapshot = nil
        campaignId = nil
        routeAssignmentId = nil
        currentFarmExecutionContext = nil
        targetBuildings = []
        resetVisitState()
        serverCompletedCount = nil
        autoCompleteEnabled = false
        sessionNotes = notes
        sessionMode = .doorKnocking
        sessionEndError = nil
        isDemoSession = false
        buildingCentroids = [:]
        dwellTracker = [:]
        lastAutoCompleteTime = nil
        startTime = sessionStartedAt
        pathCoordinates = []
        distanceMeters = 0
        elapsedTime = 0
        lastLocation = nil
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        progressSyncer.reset()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false
        resetBackgroundLocationUpgradePromptState()
        activeSecondsAccumulator = 0
        activeSegmentStartTime = Date()
        isPaused = false
        optimizedRoute = nil
        goalType = resolvedGoalType
        goalAmount = resolvedGoalAmount
        addressesMarkedDelivered = 0
        shareCardDoorPinCoordinates = []
        appointmentsSet = 0
        appointmentAddressIds = []
        locationError = nil
        trailNormalizer = nil
        scoredVisitEngine = nil
        streetCoverageVisitEngine = nil
        flyerTargetIds = []
        flyerCentroids = [:]
        onFlyerAddressesCompleted = nil
        sessionRoadCorridors = []
        activeSharedLiveSessionId = nil
        lastSharedLivePresencePeriodicSync = nil
        isActive = true

        requestAuthorizationAndStartLocation(for: sessionMode)
        startElapsedTimer()
        await syncLiveActivity(forceStart: true)
    }

    // MARK: - Building session (session recording)

    /// Start a door-knocking session with target buildings. Call with centroids from map features for auto-complete.
    /// Session is only marked active (sessionId, timer, location) after createSession succeeds so time/distance/path work.
    func startBuildingSession(
        campaignId: UUID,
        targetBuildings: [String],
        autoCompleteEnabled: Bool = false,
        centroids: [String: CLLocationCoordinate2D] = [:],
        notes: String? = nil,
        mode: SessionMode = .doorKnocking,
        goalType: GoalType? = nil,
        enableSharedLiveCanvassing: Bool = false,
        sharedLiveSessionIdOverride: UUID? = nil,
        goalAmountOverride: Int? = nil,
        routeAssignmentId: UUID? = nil,
        farmExecutionContext: FarmExecutionContext? = nil
    ) async throws {
        sessionRestoredThisLaunch = false
        guard let userId = AuthManager.shared.user?.id else {
            print("⚠️ [SessionManager] Cannot start building session: not authenticated")
            return
        }
        if let inFlight = startInFlightCampaignId {
            if inFlight == campaignId {
                throw SessionStartError.startAlreadyInFlight(campaignId: campaignId)
            }
            throw SessionStartError.startAlreadyInFlight(campaignId: inFlight)
        }
        if let blockReason = await CampaignsAPI.shared.sessionStartBlockReason(campaignId: campaignId) {
            throw SessionStartError.campaignNotProvisioned(campaignId: campaignId, reason: blockReason)
        }
        startInFlightCampaignId = campaignId
        defer { startInFlightCampaignId = nil }

        let newSessionId = UUID()
        let sessionStartedAt = Date()
        self.routeAssignmentId = nil
        let resolvedGoalType = goalType ?? mode.defaultGoalType
        let goalAmount: Int = {
            if let goalAmountOverride, goalAmountOverride <= 0 {
                return 0
            }
            return resolvedGoalType.normalizedAmount(
                goalAmountOverride ?? resolvedGoalType.defaultAmount(for: mode, targetCount: targetBuildings.count),
                for: mode,
                targetCount: targetBuildings.count
            )
        }()

        logSessionStart(.createSession, "begin campaign=\(campaignId.uuidString)")
        let offlinePayload = buildOfflineSessionPayload(
            sessionId: newSessionId,
            userId: userId,
            campaignId: campaignId,
            targetBuildings: targetBuildings,
            autoCompleteEnabled: autoCompleteEnabled,
            notes: notes,
            goalType: resolvedGoalType,
            goalAmount: goalAmount,
            mode: mode,
            routeAssignmentId: routeAssignmentId,
            farmExecutionContext: farmExecutionContext,
            startedAt: sessionStartedAt
        )

        await sessionRepository.createLocalSession(
            id: newSessionId,
            remoteId: nil,
            campaignId: campaignId,
            mode: mode,
            startedAt: sessionStartedAt,
            createdOffline: !NetworkMonitor.shared.isOnline,
            payload: offlinePayload
        )

        if NetworkMonitor.shared.isOnline {
            do {
                try await SessionsAPI.shared.createSession(
                    id: newSessionId,
                    userId: userId,
                    campaignId: campaignId,
                    targetBuildingIds: targetBuildings,
                    autoCompleteEnabled: autoCompleteEnabled,
                    thresholdMeters: autoCompleteThresholdMeters,
                    dwellSeconds: Int(autoCompleteDwellSeconds),
                    notes: notes,
                    workspaceId: WorkspaceContext.shared.workspaceId,
                    goalType: resolvedGoalType,
                    goalAmount: goalAmount,
                    sessionMode: mode,
                    routeAssignmentId: routeAssignmentId,
                    farmExecutionContext: farmExecutionContext,
                    startedAt: sessionStartedAt
                )
                await sessionRepository.markSessionRemoteCreated(sessionId: newSessionId)
                logSessionStart(.createSession, "success session=\(newSessionId.uuidString)")
            } catch {
                logSessionStart(.createSession, "remote create deferred error=\(error.localizedDescription)")
                await outboxRepository.enqueue(
                    entityType: "session",
                    entityId: newSessionId.uuidString,
                    operation: .createSession,
                    payload: offlinePayload,
                    dependencyKey: "session:\(newSessionId.uuidString.lowercased())"
                )
            }
        } else {
            await outboxRepository.enqueue(
                entityType: "session",
                entityId: newSessionId.uuidString,
                operation: .createSession,
                payload: offlinePayload,
                dependencyKey: "session:\(newSessionId.uuidString.lowercased())"
            )
            logSessionStart(.createSession, "queued for offline sync session=\(newSessionId.uuidString)")
        }

        do {
            try await SessionParticipantsService.shared.upsertHostParticipant(
                sessionId: newSessionId,
                campaignId: campaignId,
                userId: userId
            )
        } catch {
            if SessionParticipantsService.shared.isMissingInfrastructure(error) {
                print("⚠️ [SessionManager] session_participants not available yet; continuing without durable host membership")
            } else {
                print("⚠️ [SessionManager] Failed to register host as live session participant: \(error)")
            }
        }

        // Now set state and start tracking (timer + location)
        sessionId = newSessionId
        activeSharedLiveSessionId = nil
        lastSharedLivePresencePeriodicSync = nil
        SessionManager.lastEndedSummaryMapSnapshot = nil
        self.campaignId = campaignId
        self.routeAssignmentId = routeAssignmentId
        self.currentFarmExecutionContext = farmExecutionContext
        self.targetBuildings = targetBuildings
        resetVisitState()
        serverCompletedCount = nil
        self.autoCompleteEnabled = autoCompleteEnabled
        self.sessionNotes = notes
        self.sessionMode = mode
        sessionEndError = nil
        isDemoSession = false
        buildingCentroids = centroids.mapValues { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        dwellTracker = [:]
        lastAutoCompleteTime = nil
        startTime = sessionStartedAt
        pathCoordinates = []
        distanceMeters = 0
        elapsedTime = 0
        lastLocation = nil
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        progressSyncer.reset()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false
        resetBackgroundLocationUpgradePromptState()
        activeSecondsAccumulator = 0
        activeSegmentStartTime = Date()
        isPaused = false
        optimizedRoute = nil
        self.goalType = resolvedGoalType
        self.goalAmount = goalAmount
        addressesMarkedDelivered = 0
        shareCardDoorPinCoordinates = []
        appointmentsSet = 0
        appointmentAddressIds = []
        locationError = currentLocation == nil ? "Searching for GPS..." : nil

        requestAuthorizationAndStartLocation(for: mode)

        // Timer must run on main run loop (and .common mode so it fires during scroll/tracking)
        startElapsedTimer()
        isActive = true
        presentBackgroundLocationUpgradePromptIfNeeded()
        await syncLiveActivity(forceStart: true)
        await safetyBeaconService.restoreState(for: newSessionId, startTime: startTime)
        if let currentLocation {
            await safetyBeaconService.recordHeartbeat(location: currentLocation, isPaused: isPaused)
        }

        if enableSharedLiveCanvassing, !isDemoSession {
            let sharedLiveSessionId = sharedLiveSessionIdOverride ?? newSessionId
            activeSharedLiveSessionId = sharedLiveSessionId

            if sharedLiveSessionId != newSessionId {
                do {
                    try await SessionParticipantsService.shared.upsertParticipant(
                        sessionId: sharedLiveSessionId,
                        campaignId: campaignId,
                        userId: userId,
                        role: "member"
                    )
                } catch {
                    if SessionParticipantsService.shared.isMissingInfrastructure(error) {
                        print("⚠️ [SessionManager] session_participants not available yet; continuing without durable invitee membership")
                    } else {
                        print("⚠️ [SessionManager] Failed to register invitee as live session participant: \(error)")
                    }
                }
            }

            let joinOutcome = await sharedLiveCanvassingService.joinNonFatal(
                campaignId: campaignId,
                sessionId: sharedLiveSessionId,
                initialLocation: currentLocation
            )
            if case let .continueSolo(reason) = joinOutcome {
                activeSharedLiveSessionId = nil
                print("⚠️ [SessionManager] Shared live canvassing unavailable for this start; continuing solo: \(reason)")
            }
        } else {
            activeSharedLiveSessionId = nil
        }

        logSessionStart(.eventLog, "begin")
        await enqueueSessionEvent(
            sessionId: newSessionId,
            campaignId: campaignId,
            buildingId: nil,
            eventType: .sessionStarted,
            location: currentLocation
        )
        if NetworkMonitor.shared.isOnline {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
        logSessionStart(.eventLog, "queued")
        print("✅ [SessionManager] Started building session with \(targetBuildings.count) targets")
    }

    /// After session restore, `buildingCentroids` is cleared; map features repopulate targets.
    /// The active session flow now uses raw GPS only, so we only need refreshed centroids here.
    func rehydrateVisitInferenceFromMapTargets(_ targets: [ResolvedCampaignTarget]) {
        guard sessionId != nil, sessionMode == .doorKnocking, !targetBuildings.isEmpty else { return }
        var didAssign = false
        for gers in targetBuildings {
            guard let match = targets.first(where: { $0.id.lowercased() == gers.lowercased() }) else { continue }
            buildingCentroids[gers] = CLLocation(latitude: match.coordinate.latitude, longitude: match.coordinate.longitude)
            didAssign = true
        }
        guard didAssign else { return }
    }

    @discardableResult
    private func applyLocalCompletionState(_ targetId: String, haptic: Bool = false) async -> Bool {
        let addressIds = resolvedAddressIds(for: targetId)
        let buildingId = resolvedBuildingId(for: targetId, addressIds: addressIds)
        return await confirmVisitState(targetId: targetId, addressIds: addressIds, buildingId: buildingId, haptic: haptic)
    }

    @discardableResult
    private func applyLocalUndoState(_ targetId: String) async -> Bool {
        let targetKey = normalizeVisitKey(targetId)
        let addressIds = resolvedAddressIds(for: targetId)
        let buildingId = resolvedBuildingId(for: targetId, addressIds: addressIds)
        guard completedBuildings.contains(targetKey) else { return false }
        pendingVisitedTargets.remove(targetKey)
        confirmedVisitedTargets.remove(targetKey)
        addressIds.forEach {
            let key = normalizeAddressKey($0)
            pendingVisitedAddressIds.remove(key)
            confirmedVisitedAddressIds.remove(key)
        }
        if let buildingKey = normalizeBuildingKey(buildingId) {
            pendingVisitedBuildingIds.remove(buildingKey)
            confirmedVisitedBuildingIds.remove(buildingKey)
        }
        shareCardDoorPinsByTargetId.removeValue(forKey: targetKey)
        addressIds.forEach { shareCardDoorPinsByAddressId.removeValue(forKey: normalizeAddressKey($0)) }
        serverCompletedCount = nil
        refreshCompletedBuildingSnapshot()
        await syncLiveActivity(forceStart: false)
        return true
    }

    func markCompletionLocallyAfterPersistedOutcome(_ targetId: String, haptic: Bool = false) async {
        _ = await applyLocalCompletionState(targetId, haptic: haptic)
    }

    func markUndoLocallyAfterPersistedOutcome(_ targetId: String) async {
        _ = await applyLocalUndoState(targetId)
    }

    private func appendShareCardDoorPin(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }
        if let last = shareCardDoorPinCoordinates.last {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if a.distance(from: b) < 3 { return }
        }
        shareCardDoorPinCoordinates.append(coordinate)
        if shareCardDoorPinCoordinates.count > 400 {
            shareCardDoorPinCoordinates.removeFirst(shareCardDoorPinCoordinates.count - 400)
        }
    }

    private func storeShareCardDoorPin(targetId: String? = nil, addressId: UUID? = nil, coordinate: CLLocationCoordinate2D?) {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }
        if let addressId {
            shareCardDoorPinsByAddressId[normalizeAddressKey(addressId)] = coordinate
            return
        }
        if let targetId {
            shareCardDoorPinsByTargetId[normalizeVisitKey(targetId)] = coordinate
            return
        }
        appendShareCardDoorPin(coordinate)
    }

    private func mergedCompletedHomeCoordinatesForShareCard() -> [CLLocationCoordinate2D] {
        var seen = Set<String>()
        var out: [CLLocationCoordinate2D] = []
        func add(_ c: CLLocationCoordinate2D) {
            guard CLLocationCoordinate2DIsValid(c) else { return }
            let key = String(format: "%.5f,%.5f", c.latitude, c.longitude)
            guard seen.insert(key).inserted else { return }
            guard out.count < 280 else { return }
            out.append(c)
        }
        for id in completedBuildings.sorted() {
            if let c = buildingCentroids[id]?.coordinate {
                add(c)
            }
        }
        for c in shareCardDoorPinsByTargetId.values {
            add(c)
        }
        for c in shareCardDoorPinsByAddressId.values {
            add(c)
        }
        for c in shareCardDoorPinCoordinates {
            add(c)
        }
        return out
    }

    private func queueCandidateCompletion(
        targetId: String,
        source: SessionVisitCompletionSource,
        location: CLLocation,
        matchedDistanceMeters: Double? = nil,
        sameSide: Bool? = nil
    ) async {
        let normalizedTargetId = normalizeVisitKey(targetId)
        guard !effectiveVisitedTargets().contains(normalizedTargetId),
              inFlightVisitConfirmationTasks[normalizedTargetId] == nil else {
            return
        }

        let addressIds = resolvedAddressIds(for: targetId)
        let buildingId = resolvedBuildingId(for: targetId, addressIds: addressIds)
        guard updatePendingVisitState(
            targetId: targetId,
            addressIds: addressIds,
            buildingId: buildingId,
            haptic: true
        ) else {
            return
        }

        if let matchedDistanceMeters {
            recordMatchedDistance(matchedDistanceMeters)
        }
        if sameSide == true {
            sameSideMatchCount += 1
        } else if sameSide == false {
            oppositeSideMatchCount += 1
        }

        let pinCoordinate = buildingId.flatMap { buildingCentroids[$0]?.coordinate } ?? location.coordinate
        storeShareCardDoorPin(targetId: targetId, coordinate: pinCoordinate)

        if isDemoSession {
            _ = await confirmVisitState(targetId: targetId, addressIds: addressIds, buildingId: buildingId)
            appendVisitDebugMessage("🧪 [VisitPipeline] demo confirmed source=\(source.rawValue) target=\(targetId)")
            return
        }

        guard let campaignId, let sessionId else {
            revertPendingVisitState(
                targetId: targetId,
                addressIds: addressIds,
                buildingId: buildingId,
                reason: "missing_session_context"
            )
            appendVisitDebugMessage("⚠️ [VisitPipeline] revert source=\(source.rawValue) target=\(targetId) reason=missing_session_context")
            return
        }

        guard !addressIds.isEmpty else {
            revertPendingVisitState(
                targetId: targetId,
                addressIds: [],
                buildingId: buildingId,
                reason: "missing_target_addresses"
            )
            appendVisitDebugMessage("⚠️ [VisitPipeline] revert source=\(source.rawValue) target=\(targetId) reason=missing_target_addresses")
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.inFlightVisitConfirmationTasks.removeValue(forKey: normalizedTargetId) }
            do {
                try await VisitsAPI.shared.updateTargetStatus(
                    addressIds: addressIds,
                    campaignId: campaignId,
                    status: .delivered,
                    notes: nil,
                    sessionId: sessionId,
                    sessionTargetId: targetId,
                    sessionEventType: .flyerLeft,
                    location: location
                )
                _ = await self.confirmVisitState(targetId: targetId, addressIds: addressIds, buildingId: buildingId)
                self.appendVisitDebugMessage("✅ [VisitPipeline] confirmed source=\(source.rawValue) target=\(targetId) addresses=\(addressIds.count)")
            } catch {
                self.revertPendingVisitState(
                    targetId: targetId,
                    addressIds: addressIds,
                    buildingId: buildingId,
                    reason: error.localizedDescription
                )
                self.appendVisitDebugMessage("❌ [VisitPipeline] failed source=\(source.rawValue) target=\(targetId) error=\(error.localizedDescription)")
            }
        }
        inFlightVisitConfirmationTasks[normalizedTargetId] = task
    }

    func persistDeliveredVisitTarget(targetId: String) async throws -> (addressIds: [UUID], buildingId: String?) {
        let addressIds = resolvedAddressIds(for: targetId)
        let buildingId = resolvedBuildingId(for: targetId, addressIds: addressIds)

        if isDemoSession {
            _ = await confirmVisitState(targetId: targetId, addressIds: addressIds, buildingId: buildingId, haptic: true)
            return (addressIds, buildingId)
        }

        guard let campaignId, let sessionId else {
            throw NSError(domain: "SessionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing session context for target completion"])
        }
        guard !addressIds.isEmpty else {
            throw NSError(domain: "SessionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No address IDs resolved for target \(targetId)"])
        }

        try await VisitsAPI.shared.updateTargetStatus(
            addressIds: addressIds,
            campaignId: campaignId,
            status: .delivered,
            notes: nil,
            sessionId: sessionId,
            sessionTargetId: targetId,
            sessionEventType: .flyerLeft,
            location: currentLocation
        )
        _ = await confirmVisitState(targetId: targetId, addressIds: addressIds, buildingId: buildingId, haptic: true)
        return (addressIds, buildingId)
    }

    /// Mark a building complete (manual tap). Idempotent. Queues event if offline.
    func completeBuilding(_ buildingId: String) async throws {
        guard await applyLocalCompletionState(buildingId, haptic: true) else { return }
        guard !isDemoSession else {
            let pin = buildingCentroids[buildingId]?.coordinate ?? currentLocation?.coordinate
            storeShareCardDoorPin(targetId: buildingId, coordinate: pin)
            return
        }
        guard let sid = sessionId, let loc = currentLocation else { return }
        let pin = buildingCentroids[buildingId]?.coordinate ?? loc.coordinate
        storeShareCardDoorPin(targetId: buildingId, coordinate: pin)
        if let campaignId {
            await enqueueSessionEvent(
                sessionId: sid,
                campaignId: campaignId,
                buildingId: buildingId,
                eventType: .completedManual,
                location: loc
            )
        }
        await persistLocalActiveSessionSnapshot()
        await enqueueSessionProgressOutbox(sessionId: sid, activeSeconds: Int(elapsedTime))
    }

    func reconcileVisitedAddressMetric(addressId: UUID, status: AddressStatus) {
        let addressKey = normalizeAddressKey(addressId)
        if status == .none || status == .untouched {
            trackedVisitedAddressIds.remove(addressKey)
        } else {
            trackedVisitedAddressIds.insert(addressKey)
        }

        let nextCount = anonymousDoorHitCount + trackedVisitedAddressIds.count
        guard nextCount != addressesMarkedDelivered else { return }
        addressesMarkedDelivered = nextCount
        if sessionMode == .flyer {
            flyersDelivered = nextCount
        }
        Task {
            await queueProgressSync(force: true)
            await syncLiveActivity(forceStart: false)
        }
    }

    /// Call when user marks an address as delivered (knocked) in the location card. Used for summary "doors" count.
    func recordAddressDelivered(addressId: UUID? = nil) {
        guard sessionId != nil else { return }
        if let addressId {
            trackedVisitedAddressIds.insert(normalizeAddressKey(addressId))
            storeShareCardDoorPin(addressId: addressId, coordinate: currentLocation?.coordinate)
        } else {
            anonymousDoorHitCount += 1
            appendShareCardDoorPin(currentLocation?.coordinate)
        }
        addressesMarkedDelivered = anonymousDoorHitCount + trackedVisitedAddressIds.count
        Task {
            await queueProgressSync(force: true)
            await syncLiveActivity(forceStart: false)
        }
    }

    /// Count a conversation once per address for the active session.
    /// If no address ID is available, count the event directly.
    func recordConversation(addressId: UUID? = nil) {
        guard let sid = sessionId else { return }
        let before = conversationsHad
        if let addressId {
            if conversationAddressIds.insert(addressId).inserted {
                conversationsHad += 1
            }
        } else {
            conversationsHad += 1
        }
        guard conversationsHad != before else { return }
        guard !isDemoSession else { return }
        let latestConversations = conversationsHad
        Task {
            do {
                try await SessionsAPI.shared.updateSession(id: sid, conversations: latestConversations)
            } catch {
                print("⚠️ [SessionManager] Failed to sync conversations for active session: \(error)")
            }
            await queueProgressSync(force: true)
            await syncLiveActivity(forceStart: false)
        }
    }

    /// Count an appointment once per address for the active session.
    func recordAppointment(addressId: UUID? = nil) {
        let before = appointmentsSet
        if let addressId {
            if appointmentAddressIds.insert(addressId).inserted {
                appointmentsSet += 1
            }
        } else {
            appointmentsSet += 1
        }
        guard appointmentsSet != before else { return }
        let latestAppointments = appointmentsSet
        Task {
            if let sid = sessionId, !isDemoSession {
                do {
                    try await SessionsAPI.shared.updateSession(id: sid, appointmentsCount: latestAppointments)
                } catch {
                    print("⚠️ [SessionManager] Failed to sync appointments for active session: \(error)")
                }
            }
            await queueProgressSync(force: true)
            await syncLiveActivity(forceStart: false)
        }
    }

    func adjustConversationCount(by delta: Int) {
        guard delta != 0 else { return }
        let nextValue = max(0, conversationsHad + delta)
        guard nextValue != conversationsHad else { return }
        conversationsHad = nextValue
        guard let sid = sessionId, !isDemoSession else { return }
        let latestConversations = conversationsHad
        Task {
            do {
                try await SessionsAPI.shared.updateSession(id: sid, conversations: latestConversations)
            } catch {
                print("⚠️ [SessionManager] Failed to sync adjusted conversations for active session: \(error)")
            }
            await queueProgressSync(force: true)
            await syncLiveActivity(forceStart: false)
        }
    }

    func recordLeadCreated(count: Int = 1) {
        guard count > 0 else { return }
        leadsCreated += count
        guard let sid = sessionId else { return }
        guard !isDemoSession else { return }
        let latestLeadsCreated = leadsCreated
        Task {
            do {
                try await SessionsAPI.shared.updateSession(id: sid, leadsCreated: latestLeadsCreated)
            } catch {
                print("⚠️ [SessionManager] Failed to sync leads created for active session: \(error)")
            }
            await queueProgressSync(force: true)
            await syncLiveActivity(forceStart: false)
        }
    }

    /// Undo a completion. Idempotent. Queues event if offline.
    func undoCompletion(_ buildingId: String) async throws {
        guard await applyLocalUndoState(buildingId) else { return }
        guard !isDemoSession else { return }
        guard let sid = sessionId, let loc = currentLocation else { return }
        if let campaignId {
            await enqueueSessionEvent(
                sessionId: sid,
                campaignId: campaignId,
                buildingId: buildingId,
                eventType: .completionUndone,
                location: loc
            )
        }
        await persistLocalActiveSessionSnapshot()
        await enqueueSessionProgressOutbox(sessionId: sid, activeSeconds: Int(elapsedTime))
    }

    /// Flush queued events when back online. Call on app become active or after successful API call.
    func flushPendingEvents() async {
        guard !isDemoSession else {
            pendingEventQueue.removeAll()
            return
        }
        pendingEventQueue.removeAll()
        if NetworkMonitor.shared.isOnline {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
    }

    /// Restore active (unended) session after app kill. Call from app launch / main view onAppear.
    func restoreActiveSessionIfNeeded() async {
        guard let userId = AuthManager.shared.user?.id else {
            await liveActivityManager.end()
            return
        }
        guard sessionId == nil else {
            await syncLiveActivity(forceStart: false)
            return
        }
        if let localSession = await sessionRepository.getActiveSession() {
            await restoreLocalSession(localSession)
            print("✅ [SessionManager] Restored active session from local store \(localSession.id)")
            return
        }
        do {
            guard let session = try await SessionsAPI.shared.fetchActiveSession(userId: userId) else {
                safetyBeaconService.clearState()
                await liveActivityManager.end()
                return
            }
            guard let sid = session.id else { return }
            // Legacy route sessions may not have campaign_id. Auto-close them so only campaign sessions can resume.
            guard let restoredCampaignId = session.campaign_id else {
                print("⚠️ [SessionManager] Found legacy active session without campaign_id. Ending it automatically.")
                try? await SessionsAPI.shared.updateSession(id: sid, endTime: Date())
                safetyBeaconService.clearState()
                await liveActivityManager.end()
                return
            }
            sessionId = sid
            campaignId = restoredCampaignId
            routeAssignmentId = session.route_assignment_id
            currentFarmExecutionContext = await restoreFarmExecutionContext(from: session)
            targetBuildings = session.target_building_ids ?? []
            resetVisitState()
            do {
                let replayResponse = try await SupabaseManager.shared.client
                    .from("session_events")
                    .select("building_id")
                    .eq("session_id", value: sid.uuidString)
                    .in("event_type", values: SessionEventType.replayCompletionEventTypeRawValues)
                    .execute()
                let replayed = try JSONDecoder().decode([SessionCompletionEventRow].self, from: replayResponse.data)
                confirmedVisitedTargets = Set(replayed.compactMap(\.buildingId).filter { !$0.isEmpty }.map { $0.lowercased() })
                refreshCompletedBuildingSnapshot()
                serverCompletedCount = nil
            } catch {
                serverCompletedCount = session.completed_count
                print("⚠️ [SessionManager] Could not replay completion events for restore: \(error)")
            }
            startTime = session.start_time
            pathCoordinates = session.pathCoordinates
            lastLocation = nil
            segmentBreaks = []
            lastSimplifiedCount = 0
            cachedSimplifiedPath = []
            conversationAddressIds = []
            distanceMeters = session.distance_meters ?? 0
            elapsedTime = session.durationSeconds
            activeSecondsAccumulator = session.durationSeconds
            sessionRestoredThisLaunch = true
            isActive = true
            let serverPaused = session.is_paused ?? false
            restoredServerPausedAfterStalePrompt = serverPaused
            let sessionAge = Date().timeIntervalSince(session.start_time)
            let isStaleOpenSession = sessionAge > Self.staleActiveSessionThreshold
            staleActiveSessionNeedsResolution = true
            resetBackgroundLocationUpgradePromptState()
            showLongSessionPrompt = false
            hasShownLongSessionPrompt = false
            hasAutoEndedLongSession = false
            autoCompleteEnabled = session.auto_complete_enabled ?? false
            flyersDelivered = session.flyers_delivered ?? 0
            conversationsHad = session.conversations ?? 0
            leadsCreated = session.leadsCreated
            appointmentsSet = session.appointmentsCount
            appointmentAddressIds = []
            goalType = session.goalTypeValue
            goalAmount = max(0, session.goal_amount ?? 0)
            sessionMode = session.sessionModeValue

            isPaused = true
            activeSegmentStartTime = nil
            progressSyncer.setBaseline(
                pathCount: pathCoordinates.count,
                distanceMeters: distanceMeters,
                activeSeconds: Int(elapsedTime),
                completedCount: completedCount,
                conversations: conversationsHad,
                leadsCreated: leadsCreated,
                at: Date()
            )
            buildingCentroids = [:]
            let restoreReason = isStaleOpenSession ? "stale active" : "active"
            print("⏸️ [SessionManager] Restored \(restoreReason) session \(sid) (age \(Int(sessionAge / 60)) min) — awaiting resume or end")
        } catch {
            print("⚠️ [SessionManager] Could not restore session: \(error)")
        }
    }

    /// User chose to continue a long-running restored session after the stale prompt.
    func resumeStaleRestoredSession() async {
        guard staleActiveSessionNeedsResolution, sessionId != nil else { return }
        staleActiveSessionNeedsResolution = false
        isPaused = restoredServerPausedAfterStalePrompt
        activeSegmentStartTime = isPaused ? nil : Date()
        if !isPaused {
            requestAuthorizationAndStartLocation(for: sessionMode)
            presentBackgroundLocationUpgradePromptIfNeeded()
        }
        startElapsedTimer()
        guard let sid = sessionId, let st = startTime else { return }
        await flushPendingEvents()
        await syncLiveActivity(forceStart: true)
        await safetyBeaconService.restoreState(for: sid, startTime: st)
        if let currentLocation {
            await safetyBeaconService.recordHeartbeat(location: currentLocation, isPaused: isPaused)
        }
        print("✅ [SessionManager] Resumed stale restored session \(sid)")
    }

    /// Persist active session snapshot when app transitions to background/inactive.
    func appDidEnterBackground() async {
        guard sessionId != nil, isActive else { return }
        await queueProgressSync(force: true)
        await syncLiveActivity(forceStart: false)
    }

    /// Re-arm location updates and flush pending sync when app returns to foreground.
    func appDidBecomeActive() async {
        guard sessionId != nil, isActive else { return }
        if !isPaused {
            startLocationUpdatesIfAuthorized()
        }
        await flushPendingEvents()
        await VisitsAPI.shared.flushPending()
        if NetworkMonitor.shared.isOnline {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
        await queueProgressSync(force: true)
        await sharedLiveCanvassingService.publishPresence(location: currentLocation, isPaused: isPaused, force: true)
        await syncLiveActivity(forceStart: false)
    }

    /// Schedule a throttled progress sync for active building sessions.
    private func queueProgressSync(force: Bool) async {
        guard progressSyncer.queue(force: force) else { return }
        defer { progressSyncer.finishQueueProcessing() }

        while let shouldForce = progressSyncer.nextForceForSync() {
            await syncProgressIfNeeded(force: shouldForce)
        }
    }

    private func syncProgressIfNeeded(force: Bool) async {
        guard !isDemoSession else { return }
        guard let sid = sessionId else { return }

        let now = Date()
        let activeSeconds = Int(elapsedTime)
        let doorsHit = effectiveDoorKnockCount
        let currentFlyersDelivered = leaderboardFlyersDelivered
        guard progressSyncer.shouldSync(
            force: force,
            now: now,
            pathCount: pathCoordinates.count,
            distanceMeters: distanceMeters,
            activeSeconds: activeSeconds,
            completedCount: completedCount,
            conversations: conversationsHad,
            leadsCreated: leadsCreated,
            minDistanceDelta: minPathMovementMeters
        ) else { return }

        await persistLocalActiveSessionSnapshot()
        await enqueueSessionProgressOutbox(sessionId: sid, activeSeconds: activeSeconds)
        progressSyncer.markSynced(
            at: now,
            pathCount: pathCoordinates.count,
            distanceMeters: distanceMeters,
            activeSeconds: activeSeconds,
            completedCount: completedCount,
            conversations: conversationsHad,
            leadsCreated: leadsCreated
        )
    }

    /// Pause building session (stops timer and location updates for elapsed time)
    func pause() async {
        guard isActive, sessionId != nil, !isPaused else { return }
        activeSecondsAccumulator = currentActiveElapsedTime()
        activeSegmentStartTime = nil
        isPaused = true
        pauseStartTime = Date()
        elapsedTime = activeSecondsAccumulator
        locationManager.stopUpdatingLocation()
        headingManager.stop(reset: true)
        await sharedLiveCanvassingService.publishPresence(location: currentLocation, isPaused: true, force: true)
        guard !isDemoSession else {
            await syncLiveActivity(forceStart: false)
            return
        }
        guard let sid = sessionId else { return }
        await persistLocalActiveSessionSnapshot()
        await enqueueSessionProgressOutbox(sessionId: sid, activeSeconds: Int(elapsedTime))
        if let campaignId {
            await enqueueSessionEvent(
                sessionId: sid,
                campaignId: campaignId,
                buildingId: nil,
                eventType: .sessionPaused,
                location: currentLocation
            )
        }
        await syncLiveActivity(forceStart: false)
    }

    /// Resume building session
    func resume() async {
        guard isActive, sessionId != nil, isPaused else { return }
        isPaused = false
        pauseStartTime = nil
        activeSegmentStartTime = Date()
        elapsedTime = activeSecondsAccumulator
        if !isDemoSession {
            startLocationUpdatesIfAuthorized()
            presentBackgroundLocationUpgradePromptIfNeeded()
        }
        await sharedLiveCanvassingService.publishPresence(location: currentLocation, isPaused: false, force: true)
        guard !isDemoSession else {
            await syncLiveActivity(forceStart: false)
            return
        }
        guard let sid = sessionId else { return }
        await persistLocalActiveSessionSnapshot()
        await enqueueSessionProgressOutbox(sessionId: sid, activeSeconds: Int(elapsedTime))
        if let campaignId {
            await enqueueSessionEvent(
                sessionId: sid,
                campaignId: campaignId,
                buildingId: nil,
                eventType: .sessionResumed,
                location: currentLocation
            )
        }
        await syncLiveActivity(forceStart: false)
    }

    func setGPSProximityEnabled(_ enabled: Bool) async {
        guard autoCompleteEnabled != enabled else { return }
        autoCompleteEnabled = enabled
        dwellTracker = [:]
        lastAutoCompleteTime = nil

        guard !isDemoSession, let sid = sessionId else { return }
        do {
            try await SessionsAPI.shared.updateSession(id: sid, autoCompleteEnabled: enabled)
        } catch {
            print("⚠️ [SessionManager] Failed to persist GPS proximity setting: \(error)")
        }
    }

    /// Stop building session and persist (update existing session row, then update user stats)
    func stopBuildingSession(presentSummary: Bool = true) async {
        guard let sid = sessionId, !isEndingSession else {
            // #region agent log
            _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "early return no sessionId", data: [:], hypothesisId: "H1")
            // #endregion
            return
        }
        staleActiveSessionNeedsResolution = false
        if let ending = endInFlightSessionId, ending == sid {
            return
        }
        isEndingSession = true
        endInFlightSessionId = sid
        sessionEndError = nil
        defer {
            isEndingSession = false
            endInFlightSessionId = nil
        }
        locationManager.stopUpdatingLocation()
        headingManager.stop(reset: true)
        timer?.invalidate()
        timer = nil
        isActive = false
        isPaused = false
        currentHeading = 0
        headingState = .unavailable
        headingPresentationState = .unavailable
        headingPresentationEngine.reset()
        lastLocation = nil
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        progressSyncer.reset()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false

        // #region agent log
        let doorsForSummaryVal = effectiveDoorKnockCount
        _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "building session end", data: ["completedCount": completedCount, "addressesMarkedDelivered": addressesMarkedDelivered, "doorsForSummary": doorsForSummaryVal, "flyersDelivered": flyersDelivered, "sessionId": sid.uuidString], hypothesisId: "H2")
        // #endregion

        if !isDemoSession {
            try? await SessionEventsAPI.shared.logLifecycleEvent(
                sessionId: sid,
                eventType: .sessionEnded,
                lat: currentLocation?.coordinate.latitude,
                lon: currentLocation?.coordinate.longitude
            )
        }
        let pathGeoJSON = coordinatesToGeoJSON(pathCoordinates)
        let renderedPathSegments = simplifiedPath()
        let activeSecs = Int(elapsedTime)
        let doorsForSummary = effectiveDoorKnockCount
        let currentFlyersDelivered = leaderboardFlyersDelivered
        let sessionEndTime = Date()
        await awaitInFlightVisitConfirmations()
        await flushPendingEvents()
        if !isDemoSession {
            await VisitsAPI.shared.flushPending()
        }
        // #region agent log
        if !isDemoSession {
            do {
                try await persistEndedBuildingSession(
                    sessionId: sid,
                    completedCount: doorsForSummary,
                    activeSeconds: activeSecs,
                    pathGeoJSON: pathGeoJSON,
                    pathGeoJSONNormalized: nil,
                    flyersDelivered: currentFlyersDelivered,
                    leadsCreated: leadsCreated,
                    doorsHit: doorsForSummary,
                    endTime: sessionEndTime
                )
                if let userId = AuthManager.shared.user?.id {
                    do {
                        try await StatsService.shared.refreshUserStatsFromSessions(userID: userId)
                    } catch {
                        print("⚠️ [SessionManager] Failed to refresh user stats after ending session: \(error)")
                    }
                }
                _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "updateSession success", data: ["flyersDelivered": currentFlyersDelivered, "doorsHit": doorsForSummary], hypothesisId: "H3")
            } catch {
                _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "updateSession failed", data: ["error": String(describing: error), "flyersDelivered": currentFlyersDelivered, "doorsHit": doorsForSummary], hypothesisId: "H3")
                isActive = true
                isPaused = true
                sessionEndError = "Couldn't finish saving this session. It's still open locally, so please try ending it again."
                await syncLiveActivity(forceStart: false)
                return
            }
        }
        await safetyBeaconService.endSession(location: currentLocation)
        if !isDemoSession, let userId = AuthManager.shared.user?.id {
            do {
                try await SessionParticipantsService.shared.markParticipantLeft(
                    sessionId: sid,
                    userId: userId
                )
            } catch {
                if SessionParticipantsService.shared.isMissingInfrastructure(error) {
                    print("⚠️ [SessionManager] session_participants not available yet; skipping participant leave mark")
                } else {
                    print("⚠️ [SessionManager] Failed to mark session participant as left: \(error)")
                }
            }
        }
        await sharedLiveCanvassingService.leaveCurrentSession()
        activeSharedLiveSessionId = nil
        // #endregion
        await liveActivityManager.end()
        if !isDemoSession, let userId = AuthManager.shared.user?.id {
            Task {
                await ChallengeService.shared.evaluateBadges(for: userId, sessionID: sid)
                await ChallengeService.shared.warmShareCard(userID: userId, sessionID: sid)
            }
        }
        if !isDemoSession,
           let userId = AuthManager.shared.user?.id,
           let farmExecutionContext = currentFarmExecutionContext {
            let executionMetrics: [String: AnyCodable] = [
                "doors_hit": AnyCodable(doorsForSummary),
                "flyers_delivered": AnyCodable(currentFlyersDelivered),
                "conversations": AnyCodable(conversationsHad),
                "leads_created": AnyCodable(leadsCreated),
                "distance_meters": AnyCodable(distanceMeters),
                "active_seconds": AnyCodable(activeSecs)
            ]

            do {
                try await FarmExecutionService.shared.completeExecution(
                    context: farmExecutionContext,
                    sessionId: sid,
                    userId: userId,
                    completedAt: sessionEndTime,
                    metrics: executionMetrics
                )
            } catch {
                print("⚠️ [SessionManager] Failed to link planned farm touch to ended session: \(error)")
            }
        }
        let liveMapSnapshot = await LiveCampaignMapSnapshotStore.shared.captureSummarySnapshot()
        // Capture summary for end-session sheet before clearing (Strava-style summary).
        let summaryPath = pathCoordinates
        let completedHomeCoordinates = mergedCompletedHomeCoordinatesForShareCard()
        let snapshot = SessionSummaryData(
            distance: distanceMeters,
            time: elapsedTime,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: summaryPath,
            renderedPathSegments: renderedPathSegments,
            completedHomeCoordinates: completedHomeCoordinates,
            completedCount: doorsForSummary,
            conversationsCount: conversationsHad,
            leadsCreatedCount: leadsCreated,
            startTime: startTime,
            isNetworkingSession: isNetworkingSession,
            isDemoSession: isDemoSession
            // TODO: verify if SessionSummaryData should also receive doorsHit/flyersDelivered separately.
        )
        if presentSummary {
            SessionManager.lastEndedSummary = snapshot
            SessionManager.lastEndedSessionId = sid
            SessionManager.lastEndedSummaryMapSnapshot = liveMapSnapshot
        }
        // Clear session state first so any presented sheet (e.g. targets, lead capture) is dismissed when RecordHomeView switches away from CampaignMapView
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            sessionId = nil
            campaignId = nil
            routeAssignmentId = nil
            currentFarmExecutionContext = nil
            sessionNotes = nil
            sessionMode = .doorKnocking
            goalType = .knocks
            goalAmount = 0
            isDemoSession = false
            targetBuildings = []
            resetVisitState()
            buildingCentroids = [:]
            shareCardDoorPinCoordinates = []
            addressesMarkedDelivered = 0
            conversationsHad = 0
            leadsCreated = 0
            appointmentsSet = 0
            lastLocation = nil
            segmentBreaks = []
            lastSimplifiedCount = 0
            cachedSimplifiedPath = []
            conversationAddressIds = []
            appointmentAddressIds = []
            trailNormalizer = nil
            scoredVisitEngine = nil
            streetCoverageVisitEngine = nil
            flyerTargetIds = []
            flyerCentroids = [:]
            onFlyerAddressesCompleted = nil
            sessionRoadCorridors = []
            showLongSessionPrompt = false

            print("✅ [SessionManager] Building session ended and saved")
            if presentSummary {
                // Post summary on the next runloop tick so local map sheets/alerts can tear down first.
                DispatchQueue.main.async { [weak self] in
                    self?.pendingSessionSummary = snapshot
                    self?.pendingSessionSummarySessionId = sid
                    NotificationCenter.default.post(name: .sessionEnded, object: nil)
                }
            } else {
                NotificationCenter.default.post(name: .sessionEnded, object: nil)
            }
        }
    }

    private func persistEndedBuildingSession(
        sessionId: UUID,
        completedCount: Int,
        activeSeconds: Int,
        pathGeoJSON: String,
        pathGeoJSONNormalized: String?,
        flyersDelivered: Int,
        leadsCreated: Int,
        doorsHit: Int,
        endTime: Date
    ) async throws {
        await sessionRepository.endSession(
            id: sessionId,
            endedAt: endTime,
            distanceMeters: distanceMeters,
            pathGeoJSON: pathGeoJSON,
            pathGeoJSONNormalized: pathGeoJSONNormalized
        )
        await enqueueSessionProgressOutbox(
            sessionId: sessionId,
            activeSeconds: activeSeconds,
            operation: .endSession,
            pathGeoJSONNormalized: pathGeoJSONNormalized,
            endTime: endTime
        )
    }

    /// Flyer mode no longer uses scored road matching, but we keep this setter so other
    /// callers do not need to know about the simplification.
    func setFlyerTargets(ids: [String], centroids: [String: CLLocation]) {
        flyerTargetIds = ids
        flyerCentroids = centroids
    }

    private func checkAutoComplete(location: CLLocation) async {
        guard sessionId != nil, isActive, !isPaused else { return }
        guard autoCompleteEnabled else { return }
        if let lastTime = lastAutoCompleteTime, Date().timeIntervalSince(lastTime) < autoCompleteDebounceSeconds {
            return
        }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= autoCompleteRequiredAccuracyMeters else {
            dwellTracker = [:]
            return
        }
        guard let nearest = findNearestIncompleteBuilding(from: location) else {
            dwellTracker = [:]
            return
        }
        let distance = location.distance(from: nearest.centroid)
        guard distance <= autoCompleteThresholdMeters else {
            dwellTracker = [:]
            return
        }
        // Invalid speed (< 0) is common when stationary; treat as slow so dwell can complete.
        let speedMPS = location.speed >= 0 ? location.speed : 0
        guard speedMPS < autoCompleteMaxSpeedMPS else {
            dwellTracker = [:]
            return
        }
        let now = Date()
        if let activeDwell = dwellTracker.values.first,
           activeDwell.buildingId != nearest.buildingId {
            dwellTracker = [:]
        }
        if let dwellState = dwellTracker[nearest.buildingId] {
            let dwellTime = now.timeIntervalSince(dwellState.enteredAt)
            if dwellTime >= autoCompleteDwellSeconds {
                lastAutoCompleteTime = now
                dwellTracker = [:]
                dwellCompletionCount += 1
                await queueCandidateCompletion(
                    targetId: nearest.buildingId,
                    source: .legacyDwell,
                    location: location,
                    matchedDistanceMeters: distance
                )
            }
        } else {
            dwellTracker = [
                nearest.buildingId: DwellState(
                    buildingId: nearest.buildingId,
                    enteredAt: now,
                    location: location
                )
            ]
        }
    }

    private func findNearestIncompleteBuilding(from location: CLLocation) -> (buildingId: String, centroid: CLLocation)? {
        let incomplete = targetBuildings.filter { !effectiveVisitedTargets().contains($0.lowercased()) }
        guard !incomplete.isEmpty else { return nil }
        var best: (String, CLLocation)?
        var bestDistance: Double = .infinity
        for gersId in incomplete {
            guard let centroid = buildingCentroids[gersId] else { continue }
            let d = location.distance(from: centroid)
            if d < bestDistance {
                bestDistance = d
                best = (gersId, centroid)
            }
        }
        return best
    }

    func stop() {
        if sessionId != nil {
            Task {
                await stopBuildingSession()
            }
            return
        }
        locationManager.stopUpdatingLocation()
        headingManager.stop(reset: true)
        timer?.invalidate()
        timer = nil
        isActive = false
        sessionMode = .doorKnocking
        currentHeading = 0
        headingState = .unavailable
        headingPresentationState = .unavailable
        headingPresentationEngine.reset()
        lastLocation = nil
        segmentBreaks = []
        lastSimplifiedCount = 0
        cachedSimplifiedPath = []
        conversationAddressIds = []
        progressSyncer.reset()
        showLongSessionPrompt = false
        hasShownLongSessionPrompt = false
        hasAutoEndedLongSession = false

        let snapshot = SessionSummaryData(
            distance: distanceMeters,
            time: elapsedTime,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            renderedPathSegments: nil,
            completedCount: nil,
            conversationsCount: nil,
            leadsCreatedCount: leadsCreated,
            startTime: startTime,
            isNetworkingSession: isNetworkingSession
        )
        SessionManager.lastEndedSummary = snapshot
        Task { @MainActor in
            SessionManager.lastEndedSummaryMapSnapshot = LiveCampaignMapSnapshotStore.shared.captureSnapshot()
        }
        if let sid = sessionId {
            SessionManager.lastEndedSessionId = sid
        }
        pendingSessionSummary = snapshot
        pendingSessionSummarySessionId = sessionId
        NotificationCenter.default.post(name: .sessionEnded, object: nil)
        Task {
            await liveActivityManager.end()
            await saveToSupabase()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        guard sessionId != nil else {
            Task { @MainActor in
                currentLocation = location
                refreshHeadingPresentation(using: location)
            }
            return
        }

        let secondaryRejectionReason = sessionGPSFilter.rejectionReason(
            location: location,
            previous: lastLocation,
            isProMode: false
        )
        guard secondaryRejectionReason == nil else {
            Task { @MainActor in
                recordRejectedPoint(secondaryRejectionReason ?? .tooClose, location: location)
            }
            Task { @MainActor in
                currentLocation = location
                refreshHeadingPresentation(using: location)
                await safetyBeaconService.recordHeartbeat(location: location, isPaused: isPaused)
                await sharedLiveCanvassingService.publishPresence(location: location, isPaused: isPaused)
                if autoCompleteEnabled, sessionMode == .doorKnocking {
                    await checkAutoComplete(location: location)
                }
            }
            return
        }

        let newCoord = location.coordinate
        let addedDistance = lastLocation.map { location.distance(from: $0) } ?? 0
        let isNewSegment: Bool
        if let last = lastLocation {
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            let segmentDistance = location.distance(from: last)
            isNewSegment = timeDelta > maxTimeGapSeconds && segmentDistance > maxTimeGapDistanceMeters
        } else {
            isNewSegment = false
        }
        lastLocation = location

        Task { @MainActor in
            currentLocation = location
            refreshHeadingPresentation(using: location)
            await safetyBeaconService.recordHeartbeat(location: location, isPaused: isPaused)
            await sharedLiveCanvassingService.publishPresence(location: location, isPaused: isPaused)
            recordAcceptedRawPoint()
            if let sid = sessionId {
                await sessionRepository.appendAcceptedPoint(sessionId: sid, location: location)
            }
            if isNewSegment {
                segmentBreaks.insert(pathCoordinates.count)
                cachedSimplifiedPath = []
                lastSimplifiedCount = 0
            }
            pathCoordinates.append(newCoord)
            distanceMeters += addedDistance
            await persistLocalActiveSessionSnapshot()
            if autoCompleteEnabled, sessionMode == .doorKnocking {
                await checkAutoComplete(location: location)
            }
            await queueProgressSync(force: false)
            await syncLiveActivity(forceStart: false)
        }
    }

    func simplified(_ coords: [CLLocationCoordinate2D], toleranceMeters: Double = 5.0) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }

        let origin = coords[0]
        let cosLat = cos(origin.latitude * .pi / 180)

        func toMeters(_ coord: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            let x = (coord.longitude - origin.longitude) * 111_320 * cosLat
            let y = (coord.latitude - origin.latitude) * 110_540
            return (x, y)
        }

        func perpendicularDistance(_ point: CLLocationCoordinate2D,
                                   from start: CLLocationCoordinate2D,
                                   to end: CLLocationCoordinate2D) -> Double {
            let p = toMeters(point)
            let s = toMeters(start)
            let e = toMeters(end)
            let dx = e.x - s.x
            let dy = e.y - s.y
            let mag = sqrt(dx * dx + dy * dy)
            guard mag > 0 else { return 0 }
            let num = abs((p.x - s.x) * dy - (p.y - s.y) * dx)
            return num / mag
        }

        var maxDist = 0.0
        var maxIdx = 0
        for i in 1..<coords.count - 1 {
            let d = perpendicularDistance(coords[i], from: coords[0], to: coords[coords.count - 1])
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }

        if maxDist > toleranceMeters {
            let left = simplified(Array(coords[0...maxIdx]), toleranceMeters: toleranceMeters)
            let right = simplified(Array(coords[maxIdx...]), toleranceMeters: toleranceMeters)
            return Array(left.dropLast() + right)
        } else {
            return [coords[0], coords[coords.count - 1]]
        }
    }

    func pathSegments() -> [[CLLocationCoordinate2D]] {
        guard !pathCoordinates.isEmpty else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []

        for (i, coord) in pathCoordinates.enumerated() {
            if segmentBreaks.contains(i) && !current.isEmpty {
                segments.append(current)
                current = []
            }
            current.append(coord)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    func simplifiedPath() -> [[CLLocationCoordinate2D]] {
        let current = pathCoordinates
        if current.count - lastSimplifiedCount >= 10 || cachedSimplifiedPath.isEmpty {
            cachedSimplifiedPath = pathSegments().map { simplified($0, toleranceMeters: 5.0) }
            lastSimplifiedCount = current.count
        }
        return cachedSimplifiedPath
    }

    /// Segments to use for map polyline. The active session flow now renders a simplified raw trail only.
    var debugShowRawTrail: Bool = false

    func renderPathSegments() -> [[CLLocationCoordinate2D]] {
        return simplifiedPath()
    }

    var rawPathSegments: [[CLLocationCoordinate2D]] { simplifiedPath() }

    /// Road-based normalization has been removed from the active session flow.
    var isProGPSDebugOverlayEnabled: Bool { false }
    var proGPSDebugRawPointCount: Int { pathCoordinates.count }
    var proGPSDebugNormalizedPointCount: Int { 0 }
    var debugCurrentSideOfStreet: SideOfStreet? { nil }

    /// Debug-only: road-based normalization is not active in the simplified session flow.
    var isProNormalizationActive: Bool { false }

    /// Flyer mode now uses its own direct proximity checks only.
    var isUsingScoredVisitForFlyer: Bool {
        false
    }

    /// Check if user is near the next waypoint and mark as reached
    private func checkWaypointProximity(location: CLLocation, route: OptimizedRoute) {
        guard currentWaypointIndex < route.waypoints.count else { return }

        let waypoint = route.waypoints[currentWaypointIndex]
        let waypointLocation = CLLocation(
            latitude: waypoint.coordinate.latitude,
            longitude: waypoint.coordinate.longitude
        )

        let distance = location.distance(from: waypointLocation)

        if distance <= waypointReachedThresholdMeters {
            // Mark waypoint as completed
            completedWaypoints.insert(waypoint.id)
            print("✅ [SessionManager] Reached waypoint \(currentWaypointIndex + 1): \(waypoint.address)")

            // Move to next waypoint
            if currentWaypointIndex < route.waypoints.count - 1 {
                currentWaypointIndex += 1
                print("🗺️ [SessionManager] Moving to waypoint \(currentWaypointIndex + 1)")
            } else {
                print("🎉 [SessionManager] All waypoints completed!")
            }
        }
    }

    /// Get the next waypoint
    var nextWaypoint: RouteWaypoint? {
        guard let route = optimizedRoute,
              currentWaypointIndex < route.waypoints.count else {
            return nil
        }
        return route.waypoints[currentWaypointIndex]
    }

    /// Get progress through route (0.0 - 1.0)
    var routeProgress: Double {
        guard let route = optimizedRoute, !route.waypoints.isEmpty else {
            return 0.0
        }
        return Double(completedWaypoints.count) / Double(route.waypoints.count)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorizationStatus = status
        if isActive && (status == .authorizedWhenInUse || status == .authorizedAlways) {
            locationError = nil
            startLocationUpdatesIfAuthorized()
            presentBackgroundLocationUpgradePromptIfNeeded()
        } else if status == .denied || status == .restricted {
            headingManager.stop(reset: true)
            showBackgroundLocationUpgradePrompt = false
            locationError = "Location access denied"
            print("⚠️ [SessionManager] Location permissions denied")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = "Location access denied"
            case .locationUnknown:
                locationError = "Searching for GPS..."
            case .network:
                locationError = "Network unavailable for location"
            default:
                locationError = error.localizedDescription
            }
        } else {
            locationError = error.localizedDescription
        }
    }

    // MARK: - Supabase Save

    private func saveToSupabase() async {
        guard !isDemoSession else { return }
        guard let userId = AuthManager.shared.user?.id,
              let startTime = startTime else {
            print("⚠️ [SessionManager] Cannot save session: missing user ID or start time")
            return
        }
        // #region agent log
        _debugLogDoors(location: "SessionManager.saveToSupabase", message: "non-building session save", data: ["flyersDelivered": flyersDelivered, "userId": userId.uuidString], hypothesisId: "H5")
        // #endregion
        let endTime = Date()
        let pathGeoJSON = coordinatesToGeoJSON(pathCoordinates)

        var sessionData: [String: Any] = [
            "user_id": userId.uuidString,
            "start_time": ISO8601DateFormatter().string(from: startTime),
            "end_time": ISO8601DateFormatter().string(from: endTime),
            "doors_hit": flyersDelivered,
            "distance_meters": distanceMeters,
            "flyers_delivered": flyersDelivered,
            "conversations": conversationsHad,
            "leads_created": leadsCreated,
            "session_mode": sessionMode.rawValue,
            "goal_type": goalType.rawValue,
            "goal_amount": goalAmount,
            "path_geojson": pathGeoJSON
        ]

        if let campaignId = campaignId {
            sessionData["campaign_id"] = campaignId.uuidString
        }
        let resolvedWorkspaceId = await SessionsAPI.shared.resolveWorkspaceId(
            forCampaignId: campaignId,
            preferredWorkspaceId: WorkspaceContext.shared.workspaceId
        )
        if let workspaceId = resolvedWorkspaceId {
            sessionData["workspace_id"] = workspaceId.uuidString
        }

        // Add route data if present
        if let route = optimizedRoute {
            sessionData["route_data"] = route.toJSON()
        }
        if let notes = sessionNotes, !notes.isEmpty {
            sessionData["notes"] = notes
        }

        do {
            // Save session to Supabase
            let wrappedValues = sessionData.mapValues { AnyCodable($0) }
            struct InsertedSessionRow: Decodable {
                let id: UUID
            }

            let inserted: InsertedSessionRow = try await SupabaseManager.shared.client
                .from("sessions")
                .insert(wrappedValues)
                .select("id")
                .single()
                .execute()
                .value

            print("✅ [SessionManager] Session saved to Supabase")
            sessionNotes = nil
            Task {
                await ChallengeService.shared.evaluateBadges(for: userId, sessionID: inserted.id)
                await ChallengeService.shared.warmShareCard(userID: userId, sessionID: inserted.id)
            }

        } catch {
            print("❌ [SessionManager] Failed to save session: \(error)")
        }
    }

    // MARK: - GeoJSON Conversion

    private func coordinatesToGeoJSON(_ coordinates: [CLLocationCoordinate2D]) -> String {
        guard !coordinates.isEmpty else {
            return """
            {
              "type": "LineString",
              "coordinates": []
            }
            """
        }

        let coordsArray = coordinates.map { coord in
            "[\(coord.longitude), \(coord.latitude)]"
        }.joined(separator: ", ")

        return """
        {
          "type": "LineString",
          "coordinates": [\(coordsArray)]
        }
        """
    }

    private func syncLiveActivity(forceStart: Bool) async {
        guard !isDemoSession else {
            lastLiveActivityPeriodicSync = nil
            lastSharedLivePresencePeriodicSync = nil
            await liveActivityManager.end()
            return
        }
        guard isActive, let liveActivityState else {
            lastLiveActivityPeriodicSync = nil
            lastSharedLivePresencePeriodicSync = nil
            await liveActivityManager.end()
            return
        }

        let sessionID = sessionId?.uuidString ?? "local-session"
        if forceStart {
            lastLiveActivityPeriodicSync = nil
            lastSharedLivePresencePeriodicSync = nil
            await liveActivityManager.start(sessionID: sessionID, state: liveActivityState)
        } else {
            await liveActivityManager.update(sessionID: sessionID, state: liveActivityState)
        }
    }

    private func logSessionStart(_ phase: SessionStartPhase, _ message: String) {
        print("🧭 [\(phase.rawValue)] \(message)")
    }
}

// MARK: - Redesign Computed Properties
extension SessionManager {
    private var liveActivityDisplayCount: Int {
        goalCurrentValue
    }

    private var liveActivityGoalLabel: String {
        guard goalAmount > 0 else { return goalType.displayName }
        return goalType.goalLabelText(amount: goalAmount)
    }

    private var liveActivitySessionLabel: String {
        sessionMode.displayName
    }

    var liveActivityState: SessionLiveActivityAttributes.ContentState? {
        guard let startTime else { return nil }

        return SessionLiveActivityAttributes.ContentState(
            sessionLabel: liveActivitySessionLabel,
            goalLabel: liveActivityGoalLabel,
            metricLabel: goalType.metricLabel,
            startedAt: startTime,
            distanceMeters: distanceMeters,
            completedCount: liveActivityDisplayCount,
            conversationsCount: conversationsHad,
            goalAmount: goalAmount,
            isPaused: isPaused
        )
    }

    var formattedElapsedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = Int(elapsedTime) / 60 % 60
        let seconds = Int(elapsedTime) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDistance: String {
        let km = distanceMeters / 1000.0
        return String(format: "%.2f km", km)
    }

    var formattedPace: String {
        guard elapsedTime > 0, completedCount > 0 else { return "0.0/hr" }
        let hoursElapsed = elapsedTime / 3600.0
        let doorsPerHour = Double(completedCount) / hoursElapsed
        return String(format: "%.1f/hr", doorsPerHour)
    }

    var formattedGoalAmount: String {
        goalType.formattedGoalAmount(goalAmount)
    }

    var goalCurrentValue: Int {
        switch goalType {
        case .flyers:
            if sessionId != nil || optimizedRoute != nil {
                return max(flyersDelivered, completedWaypoints.count, completedCount)
            }
            return flyersDelivered
        case .knocks:
            if optimizedRoute != nil {
                return max(completedWaypoints.count, flyersDelivered, completedCount)
            }
            if sessionMode == .flyer {
                return max(completedCount, flyersDelivered)
            }
            return effectiveDoorKnockCount
        case .conversations:
            return conversationsHad
        case .leads:
            return leadsCreated
        case .appointments:
            return appointmentsSet
        case .time:
            return Int(elapsedTime / 60.0)
        }
    }

    var goalProgressPercentage: Double {
        guard goalAmount > 0 else { return 0 }
        switch goalType {
        case .time:
            let targetSeconds = Double(goalAmount) * 60.0
            guard targetSeconds > 0 else { return 0 }
            return min(elapsedTime / targetSeconds, 1.0)
        default:
            return min(Double(goalCurrentValue) / Double(goalAmount), 1.0)
        }
    }

    var goalProgressText: String {
        guard goalAmount > 0 else { return goalType.displayName }
        switch goalType {
        case .appointments:
            return appointmentsSet > 0 ? "Appointment booked" : "Appointment goal"
        default:
            return "Goal \(goalCurrentValue)/\(goalAmount) \(goalType.progressMetricLabel)"
        }
    }

    /// Goal progress (0.0 to 1.0) for the active session goal.
    var countProgress: Double? {
        goalProgressPercentage
    }

    /// Incomplete building IDs sorted by distance from current location, limited to 20.
    var nextTargetBuildingIds: [(buildingId: String, distance: Double)] {
        let incomplete = targetBuildings.filter { !effectiveVisitedTargets().contains($0.lowercased()) }
        guard !incomplete.isEmpty else { return [] }
        guard let userLocation = currentLocation else {
            return incomplete.prefix(20).map { ($0, Double.infinity) }
        }
        return incomplete
            .compactMap { id -> (String, Double)? in
                guard let centroid = buildingCentroids[id] else { return nil }
                return (id, userLocation.distance(from: centroid))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(20)
            .map { ($0.0, $0.1) }
    }
}

// MARK: - Dwell state for auto-complete
private struct DwellState {
    let buildingId: String
    let enteredAt: Date
    let location: CLLocation
}// MARK: - Pending event for offline queue
private struct PendingSessionEvent {
    let sessionId: UUID
    let buildingId: String
    let eventType: SessionEventType
    let lat: Double
    let lon: Double
    let metadata: [String: Any]
}

// MARK: - Restore Replay Helpers
private struct SessionCompletionEventRow: Decodable {
    let buildingId: String?

    enum CodingKeys: String, CodingKey {
        case buildingId = "building_id"
    }
}

// MARK: - Session GPS Filter
private struct SessionGPSFilter {
    let minPathMovementMeters: Double
    let maxHorizontalAccuracy: Double
    let minSpeed: Double
    let stationarySpeedThreshold: Double
    let stationaryMovementMeters: Double
    let stationaryAccuracyMultiplier: Double
    let stationaryMinImpliedSpeedMPS: Double
    let maxImpliedSpeedMPS: Double

    func rejectionReason(location: CLLocation, previous: CLLocation?, isProMode: Bool) -> RejectionReason? {
        if !isProMode {
            guard location.horizontalAccuracy > 0,
                  location.horizontalAccuracy <= maxHorizontalAccuracy else { return .poorAccuracy }
        }
        guard let previous else { return nil }

        let speedValid = location.speed >= 0
        let isStationary = !speedValid || location.speed < stationarySpeedThreshold
        let segmentDistance = location.distance(from: previous)
        let timeDelta = location.timestamp.timeIntervalSince(previous.timestamp)
        let impliedSpeed = timeDelta > 0 ? segmentDistance / timeDelta : 0
        guard impliedSpeed < maxImpliedSpeedMPS else { return .tooFast }

        let speedOK = !speedValid || location.speed >= minSpeed
        guard speedOK else { return .tooClose }

        let requiredDistance = requiredMovementDistance(
            isStationary: isStationary,
            current: location,
            previous: previous
        )
        guard segmentDistance >= requiredDistance else { return .tooClose }

        if isStationary && impliedSpeed < stationaryMinImpliedSpeedMPS {
            return .tooClose
        }
        return nil
    }

    func shouldAccept(location: CLLocation, previous: CLLocation?, isProMode: Bool) -> Bool {
        rejectionReason(location: location, previous: previous, isProMode: isProMode) == nil
    }

    private func requiredMovementDistance(
        isStationary: Bool,
        current: CLLocation,
        previous: CLLocation
    ) -> Double {
        let base = isStationary ? stationaryMovementMeters : minPathMovementMeters
        let currentAccuracy = max(0, current.horizontalAccuracy)
        let previousAccuracy = max(0, previous.horizontalAccuracy)
        let combinedAccuracy = currentAccuracy + previousAccuracy
        let uncertaintyFloor = combinedAccuracy * stationaryAccuracyMultiplier
        return max(base, uncertaintyFloor)
    }
}

// MARK: - Session Progress Sync State
private struct SessionProgressSyncer {
    private(set) var lastProgressSyncAt: Date?
    private(set) var lastSyncedPathCount: Int = 0
    private(set) var lastSyncedDistanceMeters: Double = 0
    private(set) var lastSyncedActiveSeconds: Int = 0
    private(set) var lastSyncedCompletedCount: Int = 0
    private(set) var lastSyncedConversations: Int = 0
    private(set) var lastSyncedLeadsCreated: Int = 0

    private var isSyncingProgress = false
    private var pendingProgressSync = false
    private var pendingForcedProgressSync = false
    private let progressSyncPointDelta = 8
    private let progressSyncIntervalSeconds: TimeInterval = 20

    mutating func reset() {
        lastProgressSyncAt = nil
        lastSyncedPathCount = 0
        lastSyncedDistanceMeters = 0
        lastSyncedActiveSeconds = 0
        lastSyncedCompletedCount = 0
        lastSyncedConversations = 0
        lastSyncedLeadsCreated = 0
        isSyncingProgress = false
        pendingProgressSync = false
        pendingForcedProgressSync = false
    }

    mutating func setBaseline(
        pathCount: Int,
        distanceMeters: Double,
        activeSeconds: Int,
        completedCount: Int,
        conversations: Int,
        leadsCreated: Int,
        at: Date
    ) {
        lastSyncedPathCount = pathCount
        lastSyncedDistanceMeters = distanceMeters
        lastSyncedActiveSeconds = activeSeconds
        lastSyncedCompletedCount = completedCount
        lastSyncedConversations = conversations
        lastSyncedLeadsCreated = leadsCreated
        lastProgressSyncAt = at
    }

    mutating func queue(force: Bool) -> Bool {
        pendingProgressSync = true
        if force {
            pendingForcedProgressSync = true
        }
        guard !isSyncingProgress else { return false }
        isSyncingProgress = true
        return true
    }

    mutating func nextForceForSync() -> Bool? {
        guard pendingProgressSync else { return nil }
        let shouldForce = pendingForcedProgressSync
        pendingProgressSync = false
        pendingForcedProgressSync = false
        return shouldForce
    }

    mutating func finishQueueProcessing() {
        isSyncingProgress = false
    }

    func shouldSync(
        force: Bool,
        now: Date,
        pathCount: Int,
        distanceMeters: Double,
        activeSeconds: Int,
        completedCount: Int,
        conversations: Int,
        leadsCreated: Int,
        minDistanceDelta: Double
    ) -> Bool {
        let pointsAdded = pathCount - lastSyncedPathCount
        let timeSinceLastSync = now.timeIntervalSince(lastProgressSyncAt ?? .distantPast)
        let stateChanged =
            abs(distanceMeters - lastSyncedDistanceMeters) >= minDistanceDelta ||
            activeSeconds != lastSyncedActiveSeconds ||
            completedCount != lastSyncedCompletedCount ||
            conversations != lastSyncedConversations ||
            leadsCreated != lastSyncedLeadsCreated
        let shouldSync = force ||
            pointsAdded >= progressSyncPointDelta ||
            timeSinceLastSync >= progressSyncIntervalSeconds
        return shouldSync && (stateChanged || force)
    }

    mutating func markSynced(
        at: Date,
        pathCount: Int,
        distanceMeters: Double,
        activeSeconds: Int,
        completedCount: Int,
        conversations: Int,
        leadsCreated: Int
    ) {
        lastProgressSyncAt = at
        lastSyncedPathCount = pathCount
        lastSyncedDistanceMeters = distanceMeters
        lastSyncedActiveSeconds = activeSeconds
        lastSyncedCompletedCount = completedCount
        lastSyncedConversations = conversations
        lastSyncedLeadsCreated = leadsCreated
    }
}
