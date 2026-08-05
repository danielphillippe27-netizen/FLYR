import Foundation

/// Stateful progress constraint: rejects (or can damp) large backward jumps along the corridor.
final class ProgressConstraint {
    private var lastAcceptedProgressMeters: Double?
    private let backwardToleranceMeters: Double

    var lastAcceptedProgress: Double? { lastAcceptedProgressMeters }

    init(backwardToleranceMeters: Double) {
        self.backwardToleranceMeters = backwardToleranceMeters
    }

    /// Returns true if the projected progress is acceptable (forward or small backward).
    func accept(projectedProgressMeters: Double) -> Bool {
        guard let last = lastAcceptedProgressMeters else {
            lastAcceptedProgressMeters = projectedProgressMeters
            return true
        }
        let delta = projectedProgressMeters - last
        if delta >= 0 {
            lastAcceptedProgressMeters = projectedProgressMeters
            return true
        }
        if -delta <= backwardToleranceMeters {
            lastAcceptedProgressMeters = projectedProgressMeters
            return true
        }
        return false
    }

    func reset() {
        lastAcceptedProgressMeters = nil
    }
}
