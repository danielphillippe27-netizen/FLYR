import ActivityKit
import Foundation

struct SessionLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sessionLabel: String
        var goalLabel: String
        var startedAt: Date
        var distanceMeters: Double
        var completedCount: Int
        var conversationsCount: Int
        var goalAmount: Int
        var isPaused: Bool
    }

    var sessionID: String
}

extension SessionLiveActivityAttributes.ContentState {
    var progressFraction: Double {
        guard goalAmount > 0 else { return 0 }
        return min(Double(completedCount) / Double(goalAmount), 1.0)
    }

    var formattedDistance: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters.rounded())) m"
    }

    var progressText: String {
        guard goalAmount > 0 else { return "\(completedCount)" }
        return "\(completedCount)/\(goalAmount)"
    }
}
