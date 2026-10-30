import Foundation
import CoreLocation

/// A replay preserves relative elapsed time from the recorded GPS and visit events.
struct RecordedReplayPoint {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

struct RecordedReplayVisit {
    let timestamp: Date
    let addressID: UUID?
    let buildingID: String?
    let status: String
}

struct RecordedReplayTimeline {
    let points: [RecordedReplayPoint]
    let visits: [RecordedReplayVisit]
    let start: Date
    let duration: TimeInterval
    let gapEndFractions: [Double]

    init?(points: [RecordedReplayPoint], visits: [RecordedReplayVisit]) {
        let valid = points.enumerated().filter { CLLocationCoordinate2DIsValid($0.element.coordinate) && $0.element.timestamp.timeIntervalSince1970.isFinite }
            .sorted { left, right in
                left.element.timestamp == right.element.timestamp ? left.offset < right.offset : left.element.timestamp < right.element.timestamp
            }.map(\.element)
        guard valid.count >= 2, let first = valid.first, let last = valid.last,
              last.timestamp > first.timestamp else { return nil }
        for (previous, next) in zip(valid, valid.dropFirst()) where previous.timestamp == next.timestamp {
            guard previous.coordinate.latitude == next.coordinate.latitude,
                  previous.coordinate.longitude == next.coordinate.longitude else { return nil }
        }
        let validVisits = visits.enumerated().filter { $0.element.timestamp.timeIntervalSince1970.isFinite }
            .sorted { left, right in
                left.element.timestamp == right.element.timestamp ? left.offset < right.offset : left.element.timestamp < right.element.timestamp
            }.map(\.element)
        self.points = valid
        self.start = min(first.timestamp, validVisits.first?.timestamp ?? first.timestamp)
        let end = max(last.timestamp, validVisits.last?.timestamp ?? last.timestamp)
        self.duration = end.timeIntervalSince(self.start)
        self.visits = validVisits
        let origin = self.start
        let totalDuration = self.duration
        self.gapEndFractions = zip(valid, valid.dropFirst()).compactMap { previous, next in
            guard next.timestamp.timeIntervalSince(previous.timestamp) > 30 else { return nil }
            return next.timestamp.timeIntervalSince(origin) / totalDuration
        }
    }

    func coordinate(at fraction: Double) -> CLLocationCoordinate2D {
        let target = start.addingTimeInterval(duration * min(1, max(0, fraction)))
        guard target > points[0].timestamp else { return points[0].coordinate }
        var low = 1
        var high = points.count - 1
        while low < high {
            let middle = (low + high) / 2
            if points[middle].timestamp < target { low = middle + 1 } else { high = middle }
        }
        let a = points[low - 1]
        let b = points[low]
        let span = b.timestamp.timeIntervalSince(a.timestamp)
        guard span > 0 else { return b.coordinate }
        // A long missing-GPS interval is unknown, not evidence of continuous movement.
        if span > 30 { return target < b.timestamp ? a.coordinate : b.coordinate }
        let t = min(1, max(0, target.timeIntervalSince(a.timestamp) / span))
        var longitudeDelta = b.coordinate.longitude - a.coordinate.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        var longitude = a.coordinate.longitude + longitudeDelta * t
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return CLLocationCoordinate2D(latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * t,
                                      longitude: longitude)
    }

    func timeFraction(for visit: RecordedReplayVisit) -> Double {
        min(1, max(0, visit.timestamp.timeIntervalSince(start) / duration))
    }
}
