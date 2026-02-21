import Foundation
import CoreLocation
import Combine
import Supabase
import UIKit

enum SessionMode: String, Codable {
    case doorKnocking = "door_knocking"
    case flyer = "flyer"

    var goalType: GoalType {
        switch self {
        case .doorKnocking:
            return .knocks
        case .flyer:
            return .flyers
        }
    }
}

// #region agent log
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
    let path = "/Users/danielphillippe/Desktop/FLYR IOS/.cursor/debug.log"
    let lineWithNewline = line + "\n"
    guard let dataToWrite = lineWithNewline.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(dataToWrite)
        try? handle.close()
    } else {
        try? dataToWrite.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
// #endregion

@MainActor
class SessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SessionManager()
    /// Snapshot for end-session summary (building session); consumed by MapView then cleared.
    static var lastEndedSummary: SessionSummaryData?

    /// Set when a session ends so the UI can show the summary sheet. Observed by RecordHomeView.
    @Published var pendingSessionSummary: SessionSummaryData?

    @Published var isActive = false
    @Published var pathCoordinates: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var startTime: Date?
    @Published var elapsedTime: TimeInterval = 0
    @Published var goalType: GoalType = .flyers
    @Published var sessionMode: SessionMode = .doorKnocking
    @Published var goalAmount: Int = 0
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLLocationDirection = 0
    @Published var flyersDelivered: Int = 0
    @Published var conversationsHad: Int = 0
    
    // Route-based session properties
    @Published var optimizedRoute: OptimizedRoute?
    @Published var currentWaypointIndex: Int = 0
    @Published var completedWaypoints: Set<UUID> = []
    @Published var campaignId: UUID?
    /// Notes for the current session (set at start, saved to Supabase)
    @Published var sessionNotes: String?

    // MARK: - Building session (session recording)
    @Published var sessionId: UUID?
    @Published var targetBuildings: [String] = [] // gers_ids
    @Published var completedBuildings: Set<String> = []
    @Published var autoCompleteEnabled = false
    @Published var isPaused = false
    /// GPS/location error state for UI (e.g. "Searching for GPS...", "Location denied")
    @Published var locationError: String?

    /// Centroids for auto-complete: gers_id -> location. Set when starting building session.
    var buildingCentroids: [String: CLLocation] = [:]

    /// Count of addresses user marked as delivered (knocked) this session via the location card. Used for summary "doors" when no building targets.
    @Published var addressesMarkedDelivered: Int = 0

    var targetCount: Int { targetBuildings.count }
    /// When restored from server without event replay, use server value; else use local set count
    private var serverCompletedCount: Int?
    var completedCount: Int { serverCompletedCount ?? completedBuildings.count }
    var remainingCount: Int { max(0, targetCount - completedCount) }
    var progressPercentage: Double {
        targetCount > 0 ? Double(completedCount) / Double(targetCount) : 0
    }

    var autoCompleteThresholdMeters: Double = 15.0
    var autoCompleteDwellSeconds: Double = 8.0
    var autoCompleteMaxSpeedMPS: Double = 2.5
    private var dwellTracker: [String: DwellState] = [:]
    private var lastAutoCompleteTime: Date?
    private let autoCompleteDebounceSeconds: Double = 3.0

    private var timer: Timer?
    private var locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    /// Ignore GPS jitter when stationary: only add a path point if moved at least this many meters from last recorded point (Strava-style smooth trail; avoids scribble at doors).
    private let minPathMovementMeters: Double = 3.0
    private let waypointReachedThresholdMeters: Double = 10.0
    private var activeSecondsAccumulator: TimeInterval = 0
    private var pauseStartTime: Date?
    private var pendingEventQueue: [PendingSessionEvent] = []
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0 // Update every 5 meters
    }
    
    func start(goalType: GoalType, goalAmount: Int) {
        self.goalType = goalType
        self.sessionMode = (goalType == .flyers) ? .flyer : .doorKnocking
        self.goalAmount = goalAmount
        self.startTime = Date()
        self.pathCoordinates = []
        self.distanceMeters = 0
        self.elapsedTime = 0
        self.lastLocation = nil
        self.optimizedRoute = nil
        self.currentWaypointIndex = 0
        self.completedWaypoints = []
        self.campaignId = nil
        self.flyersDelivered = 0
        self.conversationsHad = 0
        
        isActive = true
        
        // Request location permissions
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        
        // Start timer for elapsed time
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    /// Start a route-based session with optimized waypoints
    func start(goalType: GoalType, goalAmount: Int? = nil, route: OptimizedRoute, campaignId: UUID?) {
        self.goalType = goalType
        self.sessionMode = (goalType == .flyers) ? .flyer : .doorKnocking
        self.goalAmount = goalAmount ?? route.stopCount
        self.startTime = Date()
        self.pathCoordinates = []
        self.distanceMeters = 0
        self.elapsedTime = 0
        self.lastLocation = nil
        self.optimizedRoute = route
        self.currentWaypointIndex = 0
        self.completedWaypoints = []
        self.campaignId = campaignId
        self.flyersDelivered = 0
        self.conversationsHad = 0
        
        isActive = true
        
        // Request location permissions
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        
        // Start timer for elapsed time
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
        
        print("✅ [SessionManager] Started route-based session with \(route.stopCount) waypoints")
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
        mode: SessionMode = .doorKnocking
    ) async throws {
        guard let userId = AuthManager.shared.user?.id else {
            print("⚠️ [SessionManager] Cannot start building session: not authenticated")
            return
        }
        let newSessionId = UUID()

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
            goalType: mode.goalType
        )

        // Now set state and start tracking (timer + location)
        sessionId = newSessionId
        self.campaignId = campaignId
        self.targetBuildings = targetBuildings
        completedBuildings = []
        serverCompletedCount = nil
        self.autoCompleteEnabled = autoCompleteEnabled
        self.sessionNotes = notes
        self.sessionMode = mode
        buildingCentroids = centroids.mapValues { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        dwellTracker = [:]
        lastAutoCompleteTime = nil
        startTime = Date()
        pathCoordinates = []
        distanceMeters = 0
        elapsedTime = 0
        lastLocation = nil
        activeSecondsAccumulator = 0
        isPaused = false
        optimizedRoute = nil
        goalType = mode.goalType
        goalAmount = targetBuildings.count
        addressesMarkedDelivered = 0
        locationError = currentLocation == nil ? "Searching for GPS..." : nil

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }

        // Timer must run on main run loop (and .common mode so it fires during scroll/tracking)
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.startTime else { return }
                if self.isPaused {
                    return
                }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isActive = true

        try await SessionEventsAPI.shared.logLifecycleEvent(
            sessionId: newSessionId,
            eventType: .sessionStarted,
            lat: currentLocation?.coordinate.latitude,
            lon: currentLocation?.coordinate.longitude
        )
        print("✅ [SessionManager] Started building session with \(targetBuildings.count) targets")
    }

    /// Mark a building complete (manual tap). Idempotent. Queues event if offline.
    func completeBuilding(_ buildingId: String) async throws {
        guard !completedBuildings.contains(buildingId) else { return }
        completedBuildings.insert(buildingId)
        serverCompletedCount = nil
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        guard let sid = sessionId, let loc = currentLocation else { return }
        await flushPendingEvents()
        do {
            try await SessionEventsAPI.shared.logEvent(
                sessionId: sid,
                buildingId: buildingId,
                eventType: .completedManual,
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                metadata: [:]
            )
            try? await SessionsAPI.shared.updateSession(id: sid, completedCount: completedCount)
        } catch {
            pendingEventQueue.append(PendingSessionEvent(
                sessionId: sid,
                buildingId: buildingId,
                eventType: .completedManual,
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                metadata: [:]
            ))
        }
    }

    /// Call when user marks an address as delivered (knocked) in the location card. Used for summary "doors" count.
    func recordAddressDelivered() {
        guard sessionId != nil else { return }
        addressesMarkedDelivered += 1
    }

    /// Undo a completion. Idempotent. Queues event if offline.
    func undoCompletion(_ buildingId: String) async throws {
        guard completedBuildings.contains(buildingId) else { return }
        completedBuildings.remove(buildingId)
        serverCompletedCount = nil
        guard let sid = sessionId, let loc = currentLocation else { return }
        do {
            try await SessionEventsAPI.shared.logEvent(
                sessionId: sid,
                buildingId: buildingId,
                eventType: .completionUndone,
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                metadata: [:]
            )
            try? await SessionsAPI.shared.updateSession(id: sid, completedCount: completedCount)
        } catch {
            pendingEventQueue.append(PendingSessionEvent(
                sessionId: sid,
                buildingId: buildingId,
                eventType: .completionUndone,
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                metadata: [:]
            ))
        }
    }

    /// Flush queued events when back online. Call on app become active or after successful API call.
    func flushPendingEvents() async {
        while let first = pendingEventQueue.first {
            do {
                try await SessionEventsAPI.shared.logEvent(
                    sessionId: first.sessionId,
                    buildingId: first.buildingId,
                    eventType: first.eventType,
                    lat: first.lat,
                    lon: first.lon,
                    metadata: first.metadata
                )
                pendingEventQueue.removeFirst()
                if let sid = sessionId {
                    try? await SessionsAPI.shared.updateSession(id: sid, completedCount: completedCount)
                }
            } catch {
                break
            }
        }
    }

    /// Restore active (unended) session after app kill. Call from app launch / main view onAppear.
    func restoreActiveSessionIfNeeded() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard sessionId == nil else { return }
        do {
            guard let session = try await SessionsAPI.shared.fetchActiveSession(userId: userId) else { return }
            guard let sid = session.id else { return }
            sessionId = sid
            campaignId = session.campaign_id
            targetBuildings = session.target_building_ids ?? []
            completedBuildings = [] // event replay would repopulate; for now leave empty
            serverCompletedCount = session.completed_count
            startTime = session.start_time
            pathCoordinates = []
            distanceMeters = session.distance_meters ?? 0
            elapsedTime = Date().timeIntervalSince(session.start_time)
            isActive = true
            isPaused = session.is_paused ?? false
            autoCompleteEnabled = session.auto_complete_enabled ?? false
            if let rawGoal = session.goal_type, rawGoal == GoalType.flyers.rawValue {
                sessionMode = .flyer
            } else {
                sessionMode = .doorKnocking
            }
            buildingCentroids = [:]
            await flushPendingEvents()
            print("✅ [SessionManager] Restored active session \(sid)")
        } catch {
            print("⚠️ [SessionManager] Could not restore session: \(error)")
        }
    }

    /// Pause building session (stops timer and location updates for elapsed time)
    func pause() async {
        guard isActive, sessionId != nil else { return }
        isPaused = true
        pauseStartTime = Date()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        guard let sid = sessionId else { return }
        try? await SessionEventsAPI.shared.logLifecycleEvent(
            sessionId: sid,
            eventType: .sessionPaused,
            lat: currentLocation?.coordinate.latitude,
            lon: currentLocation?.coordinate.longitude
        )
    }

    /// Resume building session
    func resume() async {
        guard isActive, sessionId != nil else { return }
        isPaused = false
        pauseStartTime = nil
        if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        guard let sid = sessionId else { return }
        try? await SessionEventsAPI.shared.logLifecycleEvent(
            sessionId: sid,
            eventType: .sessionResumed,
            lat: currentLocation?.coordinate.latitude,
            lon: currentLocation?.coordinate.longitude
        )
    }

    /// Stop building session and persist (update existing session row, then update user stats)
    func stopBuildingSession() async {
        guard let sid = sessionId else {
            // #region agent log
            _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "early return no sessionId", data: [:], hypothesisId: "H1")
            // #endregion
            return
        }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        timer?.invalidate()
        timer = nil
        isActive = false
        isPaused = false

        // #region agent log
        let doorsForSummaryVal = max(completedCount, addressesMarkedDelivered)
        _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "building session end", data: ["completedCount": completedCount, "addressesMarkedDelivered": addressesMarkedDelivered, "doorsForSummary": doorsForSummaryVal, "sessionId": sid.uuidString], hypothesisId: "H2")
        // #endregion

        try? await SessionEventsAPI.shared.logLifecycleEvent(
            sessionId: sid,
            eventType: .sessionEnded,
            lat: currentLocation?.coordinate.latitude,
            lon: currentLocation?.coordinate.longitude
        )
        let pathGeoJSON = coordinatesToGeoJSON(pathCoordinates)
        let activeSecs = Int(elapsedTime)
        // Use doors/knocks for both session row and user_stats so leaderboard and "You" stats match
        let doorsForSummary = max(completedCount, addressesMarkedDelivered)
        // #region agent log
        do {
            try await SessionsAPI.shared.updateSession(
                id: sid,
                completedCount: doorsForSummary,
                distanceM: distanceMeters,
                activeSeconds: activeSecs,
                pathGeoJSON: pathGeoJSON,
                flyersDelivered: doorsForSummary,
                conversations: conversationsHad,
                doorsHit: doorsForSummary,
                endTime: Date()
            )
            _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "updateSession success", data: ["flyersDelivered": doorsForSummary], hypothesisId: "H3")
        } catch {
            _debugLogDoors(location: "SessionManager.stopBuildingSession", message: "updateSession failed", data: ["error": String(describing: error), "flyersDelivered": doorsForSummary], hypothesisId: "H3")
        }
        // #endregion
        if let userId = AuthManager.shared.user?.id {
            await updateUserStats(userId: userId, flyersOverride: doorsForSummary)
        }
        // Capture summary for end-session sheet before clearing (Strava-style summary).
        // Path is already saved to Supabase above via pathGeoJSON; snapshot uses same pathCoordinates for the summary sheet route mini-map.
        let snapshot = SessionSummaryData(
            distance: distanceMeters,
            time: elapsedTime,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            completedCount: doorsForSummary,
            conversationsCount: conversationsHad,
            startTime: startTime
        )
        SessionManager.lastEndedSummary = snapshot
        // Clear session state first so any presented sheet (e.g. targets, lead capture) is dismissed when RecordHomeView switches away from CampaignMapView
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            sessionId = nil
            campaignId = nil
            sessionNotes = nil
            sessionMode = .doorKnocking
            targetBuildings = []
            completedBuildings = []
            buildingCentroids = [:]
            addressesMarkedDelivered = 0
            conversationsHad = 0

            print("✅ [SessionManager] Building session ended and saved")
            // Delay summary so CampaignMapView (and any sheet) is torn down first, avoiding "only presenting a single sheet"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.pendingSessionSummary = snapshot
                NotificationCenter.default.post(name: .sessionEnded, object: nil)
            }
        }
    }

    private func checkAutoComplete(location: CLLocation) async {
        guard autoCompleteEnabled, sessionId != nil, isActive, !isPaused else { return }
        if let lastTime = lastAutoCompleteTime, Date().timeIntervalSince(lastTime) < autoCompleteDebounceSeconds {
            return
        }
        guard let nearest = findNearestIncompleteBuilding(from: location) else {
            return
        }
        let distance = location.distance(from: nearest.centroid)
        guard distance <= autoCompleteThresholdMeters else {
            dwellTracker[nearest.buildingId] = nil
            return
        }
        guard location.speed >= 0 && location.speed < autoCompleteMaxSpeedMPS else { return }
        let now = Date()
        if var dwellState = dwellTracker[nearest.buildingId] {
            let dwellTime = now.timeIntervalSince(dwellState.enteredAt)
            if dwellTime >= autoCompleteDwellSeconds {
                lastAutoCompleteTime = now
                dwellTracker[nearest.buildingId] = nil
                completedBuildings.insert(nearest.buildingId)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                guard let sid = sessionId else { return }
                try? await SessionEventsAPI.shared.logEvent(
                    sessionId: sid,
                    buildingId: nearest.buildingId,
                    eventType: .completedAuto,
                    lat: location.coordinate.latitude,
                    lon: location.coordinate.longitude,
                    metadata: [
                        "distance_m": distance,
                        "dwell_seconds": dwellTime,
                        "speed_mps": location.speed,
                        "threshold_m": autoCompleteThresholdMeters,
                    ] as [String: Any]
                )
                try? await SessionsAPI.shared.updateSession(id: sid, completedCount: completedCount)
            }
        } else {
            dwellTracker[nearest.buildingId] = DwellState(buildingId: nearest.buildingId, enteredAt: now, location: location)
        }
    }

    private func findNearestIncompleteBuilding(from location: CLLocation) -> (buildingId: String, centroid: CLLocation)? {
        let incomplete = targetBuildings.filter { !completedBuildings.contains($0) }
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
        locationManager.stopUpdatingHeading()
        timer?.invalidate()
        timer = nil
        isActive = false
        sessionMode = .doorKnocking

        let snapshot = SessionSummaryData(
            distance: distanceMeters,
            time: elapsedTime,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            completedCount: nil,
            conversationsCount: nil,
            startTime: startTime
        )
        SessionManager.lastEndedSummary = snapshot
        pendingSessionSummary = snapshot
        NotificationCenter.default.post(name: .sessionEnded, object: nil)
        Task {
            await saveToSupabase()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Delegate can be called on a background thread; push all @Published updates onto MainActor so UI and map update
        Task { @MainActor in
            locationError = nil
            currentLocation = location

            // Only record path and distance when a building session is active (red line + stats).
            // Require minimum movement so GPS jitter when standing still doesn't draw a crazy path.
            if sessionId != nil {
                let shouldRecord: Bool
                if let last = lastLocation {
                    let segmentDistance = location.distance(from: last)
                    shouldRecord = segmentDistance >= minPathMovementMeters
                    if shouldRecord {
                        pathCoordinates.append(location.coordinate)
                        distanceMeters += segmentDistance
                        lastLocation = location
                    }
                } else {
                    pathCoordinates.append(location.coordinate)
                    lastLocation = location
                    shouldRecord = true
                }
                if shouldRecord {
                    await checkAutoComplete(location: location)
                }
            } else if optimizedRoute != nil {
                if let last = lastLocation {
                    let segmentDistance = location.distance(from: last)
                    if segmentDistance >= minPathMovementMeters {
                        pathCoordinates.append(location.coordinate)
                        distanceMeters += segmentDistance
                        lastLocation = location
                    }
                } else {
                    pathCoordinates.append(location.coordinate)
                    lastLocation = location
                }
            } else {
                lastLocation = location
            }

            if let route = optimizedRoute {
                checkWaypointProximity(location: location, route: route)
            }
        }
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if isActive && (status == .authorizedWhenInUse || status == .authorizedAlways) {
            locationError = nil
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else if status == .denied || status == .restricted {
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
            "goal_type": goalType.rawValue,
            "goal_amount": goalAmount,
            "path_geojson": pathGeoJSON
        ]
        
        if let campaignId = campaignId {
            sessionData["campaign_id"] = campaignId.uuidString
        }
        if let workspaceId = WorkspaceContext.shared.workspaceId {
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
            _ = try await SupabaseManager.shared.client
                .from("sessions")
                .insert(wrappedValues)
                .execute()
            
            print("✅ [SessionManager] Session saved to Supabase")
            sessionNotes = nil
            
            // Update user_stats after successful session save
            await updateUserStats(userId: userId)
            
        } catch {
            print("❌ [SessionManager] Failed to save session: \(error)")
        }
    }
    
    // MARK: - Update User Stats
    
    /// Updates user_stats with ALL session metrics (flyers, conversations, distance, time).
    /// For building sessions, pass flyersOverride (doors/knocks count) so stats reflect delivered flyers.
    private func updateUserStats(userId: UUID, flyersOverride: Int? = nil) async {
        do {
            let distanceKm = distanceMeters / 1000.0
            let timeMinutes = Int(elapsedTime / 60.0)
            let flyers = flyersOverride ?? flyersDelivered
            print("📊 [SessionManager] Updating stats: \(flyers) flyers, \(conversationsHad) conversations, \(String(format: "%.2f", distanceKm)) km, \(timeMinutes) min")
            
            // Use RPC for atomic stats update
            let params: [String: AnyCodable] = [
                "p_user_id": AnyCodable(userId.uuidString),
                "p_flyers": AnyCodable(flyers),
                "p_conversations": AnyCodable(conversationsHad),
                "p_leads": AnyCodable(0),
                "p_distance_km": AnyCodable(distanceKm),
                "p_time_minutes": AnyCodable(timeMinutes)
            ]
            
            _ = try await SupabaseManager.shared.client
                .rpc("increment_user_stats", params: params)
                .execute()
            
            print("✅ [SessionManager] User stats updated successfully")
            
        } catch {
            print("❌ [SessionManager] Failed to update user stats: \(error)")
            // Don't throw - session was saved successfully, stats update failure is non-critical
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
}

// MARK: - Redesign Computed Properties
extension SessionManager {
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

    /// Goal progress (0.0 to 1.0) for count-based goals (building session).
    var countProgress: Double? {
        guard goalAmount > 0 else { return nil }
        return min(Double(completedCount) / Double(goalAmount), 1.0)
    }

    /// Incomplete building IDs sorted by distance from current location, limited to 20.
    var nextTargetBuildingIds: [(buildingId: String, distance: Double)] {
        let incomplete = targetBuildings.filter { !completedBuildings.contains($0) }
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
