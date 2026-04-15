import Foundation
import CoreLocation

/// Light smoothing over the last N normalized coordinates (moving average).
struct TrailSmoothing {
    private let windowSize: Int
    private var buffer: [CLLocationCoordinate2D] = []

    init(windowSize: Int = 3) {
        self.windowSize = max(1, windowSize)
    }

    /// Add a new coordinate and return smoothed coordinate (once we have enough points).
    mutating func add(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        buffer.append(coordinate)
        if buffer.count > windowSize {
            buffer.removeFirst()
        }
        guard buffer.count >= min(2, windowSize) else {
            return buffer.last
        }
        let window = buffer.suffix(windowSize)
        let count = Double(window.count)
        let sumLat = window.reduce(0.0) { $0 + $1.latitude }
        let sumLon = window.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: sumLat / count, longitude: sumLon / count)
    }

    mutating func reset() {
        buffer.removeAll()
    }
}
