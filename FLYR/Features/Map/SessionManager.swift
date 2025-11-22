import Foundation
import CoreLocation
import Combine
import Supabase

@MainActor
class SessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SessionManager()
    
    @Published var isActive = false
    @Published var pathCoordinates: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var startTime: Date?
    @Published var elapsedTime: TimeInterval = 0
    @Published var goalType: GoalType = .flyers
    @Published var goalAmount: Int = 0
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLLocationDirection = 0
    
    private var timer: Timer?
    private var locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0 // Update every 5 meters
    }
    
    func start(goalType: GoalType, goalAmount: Int) {
        self.goalType = goalType
        self.goalAmount = goalAmount
        self.startTime = Date()
        self.pathCoordinates = []
        self.distanceMeters = 0
        self.elapsedTime = 0
        self.lastLocation = nil
        
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
    
    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        timer?.invalidate()
        timer = nil
        isActive = false
        
        // Trigger summary
        NotificationCenter.default.post(name: .sessionEnded, object: nil)
        
        // Save to Supabase
        Task {
            await saveToSupabase()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        pathCoordinates.append(location.coordinate)
        
        // Calculate distance
        if let lastLocation = lastLocation {
            let segmentDistance = location.distance(from: lastLocation)
            distanceMeters += segmentDistance
        }
        
        lastLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if isActive && (status == .authorizedWhenInUse || status == .authorizedAlways) {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else if status == .denied || status == .restricted {
            // Handle denied permissions
            print("⚠️ [SessionManager] Location permissions denied")
        }
    }
    
    // MARK: - Supabase Save
    
    private func saveToSupabase() async {
        guard let userId = AuthManager.shared.user?.id,
              let startTime = startTime else {
            print("⚠️ [SessionManager] Cannot save session: missing user ID or start time")
            return
        }
        
        let endTime = Date()
        let pathGeoJSON = coordinatesToGeoJSON(pathCoordinates)
        
        let sessionData: [String: Any] = [
            "user_id": userId.uuidString,
            "start_time": ISO8601DateFormatter().string(from: startTime),
            "end_time": ISO8601DateFormatter().string(from: endTime),
            "distance_meters": distanceMeters,
            "goal_type": goalType.rawValue,
            "goal_amount": goalAmount,
            "path_geojson": pathGeoJSON
        ]
        
        do {
            // Save session to Supabase
            let wrappedValues = sessionData.mapValues { AnyCodable($0) }
            _ = try await SupabaseManager.shared.client
                .from("sessions")
                .insert(wrappedValues)
                .execute()
            
            print("✅ [SessionManager] Session saved to Supabase")
            
            // Update user_stats after successful session save
            await updateUserStats(userId: userId)
            
        } catch {
            print("❌ [SessionManager] Failed to save session: \(error)")
        }
    }
    
    // MARK: - Update User Stats
    
    private func updateUserStats(userId: UUID) async {
        let statsService = StatsService.shared
        
        do {
            // Fetch current stats
            guard let currentStats = try await statsService.fetchUserStats(userID: userId) else {
                print("⚠️ [SessionManager] User stats not found, skipping stats update")
                return
            }
            
            // Calculate increments
            // distance_walked is stored in km, distanceMeters is in meters
            let distanceKm = distanceMeters / 1000.0
            let newDistance = currentStats.distance_walked + distanceKm
            
            // time_tracked is stored in minutes, elapsedTime is in seconds
            let timeMinutes = Int(elapsedTime / 60.0)
            let newTime = currentStats.time_tracked + timeMinutes
            
            // Update distance_walked
            try await statsService.updateStat(userID: userId, field: "distance_walked", value: newDistance)
            
            // Update time_tracked
            try await statsService.updateStat(userID: userId, field: "time_tracked", value: newTime)
            
            print("✅ [SessionManager] Updated user stats: +\(String(format: "%.2f", distanceKm)) km, +\(timeMinutes) min")
            
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

