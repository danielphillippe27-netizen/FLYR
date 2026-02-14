import Foundation
import CoreLocation

// MARK: - Share card session stats (adapter from SessionSummaryData)

/// Stats for the transparent share card. Pace is doors/hr from duration + doors only (no goal).
struct ShareCardSessionStats {
    let doorsKnocked: Int
    let distanceKm: Double
    let pace: String
    let duration: TimeInterval
    let routePoints: [CLLocationCoordinate2D]

    var distanceFormatted: String {
        String(format: "%.2f km", distanceKm)
    }

    var timeFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%dm %ds", minutes, seconds)
    }

    init(data: SessionSummaryData) {
        let doors = data.completedCount ?? 0
        self.doorsKnocked = doors
        self.distanceKm = data.distance / 1000.0
        if doors > 0 && data.time > 0 {
            let perHour = Double(doors) / (data.time / 3600.0)
            self.pace = String(format: "%.1f/hr", perHour)
        } else {
            self.pace = "—"
        }
        self.duration = data.time
        self.routePoints = Self.simplifyPath(data.pathCoordinates)
    }

    /// Downsample route so rendering and export stay fast. Keeps first/last and points ≥ minDistanceMeters from last kept.
    private static func simplifyPath(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let minDistanceMeters: Double = 15
        guard coordinates.count >= 3 else { return coordinates }
        var result: [CLLocationCoordinate2D] = [coordinates[0]]
        var lastKept = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        for i in 1 ..< (coordinates.count - 1) {
            let pt = coordinates[i]
            let loc = CLLocation(latitude: pt.latitude, longitude: pt.longitude)
            if loc.distance(from: lastKept) >= minDistanceMeters {
                result.append(pt)
                lastKept = loc
            }
        }
        if coordinates.count > 1 {
            result.append(coordinates[coordinates.count - 1])
        }
        return result
    }
}
