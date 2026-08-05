import Foundation
import CoreLocation

/// Result of acceptance check: either accepted (with RawTrackPoint) or rejected (with reason).
struct LocationAcceptanceResult {
    let accepted: Bool
    let rawTrackPoint: RawTrackPoint?
    let rejectionReason: RejectionReason?
}

/// Accepts or rejects raw GPS updates based on accuracy, min distance, and speed.
struct LocationAcceptanceFilter {
    private let config: GPSNormalizationConfig

    init(config: GPSNormalizationConfig) {
        self.config = config
    }

    /// Returns acceptance result. If rejected, rejectionReason is set and rawTrackPoint may be nil (we don't store rejected points in raw trail).
    func accept(location: CLLocation, lastAccepted: CLLocation?) -> LocationAcceptanceResult {
        if location.horizontalAccuracy <= 0 || location.horizontalAccuracy > config.maxHorizontalAccuracy {
            logRejection(.poorAccuracy, location: location)
            return LocationAcceptanceResult(accepted: false, rawTrackPoint: nil, rejectionReason: .poorAccuracy)
        }

        if let last = lastAccepted {
            let distance = location.distance(from: last)
            if distance < config.minMovementDistance {
                logRejection(.tooClose, location: location)
                return LocationAcceptanceResult(accepted: false, rawTrackPoint: nil, rejectionReason: .tooClose)
            }
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            if timeDelta > 0 {
                let impliedSpeed = distance / timeDelta
                if impliedSpeed > config.maxWalkingSpeedMetersPerSecond {
                    logRejection(.tooFast, location: location)
                    return LocationAcceptanceResult(accepted: false, rawTrackPoint: nil, rejectionReason: .tooFast)
                }
            }
        }

        let raw = RawTrackPoint(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            rejectionReason: nil
        )
        return LocationAcceptanceResult(accepted: true, rawTrackPoint: raw, rejectionReason: nil)
    }

    private func logRejection(_ reason: RejectionReason, location: CLLocation) {
        #if DEBUG
        print("📍 [GPSNorm] Rejected: \(reason.rawValue) hAcc=\(location.horizontalAccuracy) coord=\(location.coordinate.latitude),\(location.coordinate.longitude)")
        #endif
    }
}
