import Foundation
import CoreLocation

/// Pure geometry helpers for polyline projection and offset. Uses planar approximation in local tangent space
/// (same meter scale as SessionManager.simplified) so distances match existing behavior.
enum GeospatialUtilities {

    private static let metersPerDegreeLon = 111_320.0
    private static let metersPerDegreeLat = 110_540.0

    /// Convert a coordinate to local meters (x = easting, y = northing) relative to an origin.
    static func toMeters(_ coord: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let cosLat = cos(origin.latitude * .pi / 180)
        let x = (coord.longitude - origin.longitude) * metersPerDegreeLon * cosLat
        let y = (coord.latitude - origin.latitude) * metersPerDegreeLat
        return (x, y)
    }

    /// Convert local meters (x, y) back to a coordinate relative to origin.
    static func toCoordinate(x: Double, y: Double, origin: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let cosLat = cos(origin.latitude * .pi / 180)
        let lon = origin.longitude + x / (metersPerDegreeLon * cosLat)
        let lat = origin.latitude + y / metersPerDegreeLat
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Distance in meters between two coordinates (planar approximation around first point).
    static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let (dx, dy) = toMeters(b, origin: a)
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Project point onto segment

    /// Nearest point on the segment from `from` to `to`, and parametric progress (0...1). Clamped to segment.
    static func project(
        point: CLLocationCoordinate2D,
        ontoSegmentFrom from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> (point: CLLocationCoordinate2D, progress: Double)? {
        let origin = from
        let p = toMeters(point, origin: origin)
        let s = toMeters(from, origin: origin)
        let e = toMeters(to, origin: origin)
        let dx = e.x - s.x
        let dy = e.y - s.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else {
            return (from, 0)
        }
        let t = ((p.x - s.x) * dx + (p.y - s.y) * dy) / lengthSq
        let tClamped = max(0, min(1, t))
        let projX = s.x + tClamped * dx
        let projY = s.y + tClamped * dy
        let projected = toCoordinate(x: projX, y: projY, origin: origin)
        return (projected, tClamped)
    }

    /// Perpendicular distance from point to the line through start and end (meters). Uses same origin for all.
    static func perpendicularDistance(
        _ point: CLLocationCoordinate2D,
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        origin: CLLocationCoordinate2D
    ) -> Double {
        let p = toMeters(point, origin: origin)
        let s = toMeters(start, origin: origin)
        let e = toMeters(end, origin: origin)
        let dx = e.x - s.x
        let dy = e.y - s.y
        let mag = sqrt(dx * dx + dy * dy)
        guard mag > 0 else { return 0 }
        let num = abs((p.x - s.x) * dy - (p.y - s.y) * dx)
        return num / mag
    }

    // MARK: - Nearest point on polyline

    /// Nearest point on the polyline, segment index, and progress along the full line in meters.
    static func nearestPointOnPolyline(
        point: CLLocationCoordinate2D,
        polyline: [CLLocationCoordinate2D]
    ) -> (point: CLLocationCoordinate2D, segmentIndex: Int, progressAlongLineMeters: Double)? {
        guard polyline.count >= 2 else { return nil }
        var bestDist = Double.infinity
        var bestPoint = polyline[0]
        var bestSegmentIndex = 0
        var bestParametric: Double = 0
        var cumulativeMeters: [Double] = [0]
        var total = 0.0
        for i in 0..<(polyline.count - 1) {
            let from = polyline[i]
            let to = polyline[i + 1]
            let segLen = distanceMeters(from, to)
            total += segLen
            cumulativeMeters.append(total)
            guard let (proj, t) = project(point: point, ontoSegmentFrom: from, to: to) else { continue }
            let d = distanceMeters(point, proj)
            if d < bestDist {
                bestDist = d
                bestPoint = proj
                bestSegmentIndex = i
                bestParametric = t
            }
        }
        let progressAlongLine = cumulativeMeters[bestSegmentIndex] + bestParametric * (cumulativeMeters[bestSegmentIndex + 1] - cumulativeMeters[bestSegmentIndex])
        return (bestPoint, bestSegmentIndex, progressAlongLine)
    }

    /// Cumulative distance in meters from start of polyline to each vertex (length = polyline.count).
    static func cumulativeDistancesAlongPolyline(_ polyline: [CLLocationCoordinate2D]) -> [Double] {
        guard polyline.count >= 2 else { return polyline.isEmpty ? [] : [0] }
        var out: [Double] = [0]
        var acc = 0.0
        for i in 0..<(polyline.count - 1) {
            acc += distanceMeters(polyline[i], polyline[i + 1])
            out.append(acc)
        }
        return out
    }

    /// Perpendicular offset from a point on the segment: move `distanceMeters` to the left (positive) or right (negative) of the segment direction from `from` to `to`.
    static func perpendicularOffset(
        from point: CLLocationCoordinate2D,
        alongSegment from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        distanceMeters offset: Double
    ) -> CLLocationCoordinate2D {
        let origin = point
        let s = toMeters(from, origin: origin)
        let e = toMeters(to, origin: origin)
        var dx = e.x - s.x
        var dy = e.y - s.y
        let mag = sqrt(dx * dx + dy * dy)
        guard mag > 0 else { return point }
        dx /= mag
        dy /= mag
        let nx = -dy
        let ny = dx
        let offX = origin.longitude + (nx * offset) / (metersPerDegreeLon * cos(origin.latitude * .pi / 180))
        let offY = origin.latitude + (ny * offset) / metersPerDegreeLat
        return CLLocationCoordinate2D(latitude: offY, longitude: offX)
    }

    // MARK: - Heading (for corridor continuity / direction bias)

    /// Heading of segment from `from` to `to` in degrees [0, 360), where 0 = north, 90 = east.
    static func segmentHeadingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let (dx, dy) = toMeters(to, origin: from)
        guard dx != 0 || dy != 0 else { return 0 }
        let rad = atan2(dx, dy)
        var deg = rad * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    /// Smallest angle between two headings in degrees [0, 180].
    static func angularDifferenceDegrees(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b)
        while d > 360 { d -= 360 }
        if d > 180 { d = 360 - d }
        return d
    }

    /// Signed lateral offset in meters: positive = left of segment direction, negative = right.
    static func signedLateralOffsetMeters(
        point: CLLocationCoordinate2D,
        segmentFrom from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        origin: CLLocationCoordinate2D
    ) -> Double {
        let p = toMeters(point, origin: origin)
        let s = toMeters(from, origin: origin)
        let e = toMeters(to, origin: origin)
        let dx = e.x - s.x
        let dy = e.y - s.y
        let mag = sqrt(dx * dx + dy * dy)
        guard mag > 0 else { return 0 }
        let cross = (p.x - s.x) * dy - (p.y - s.y) * dx
        return cross / mag
    }

    // MARK: - Douglas-Peucker simplification

    /// Simplify polyline with Douglas-Peucker; tolerance in meters.
    static func douglasPeucker(_ coords: [CLLocationCoordinate2D], toleranceMeters: Double) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }
        let origin = coords[0]
        func perpDist(_ point: CLLocationCoordinate2D, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
            perpendicularDistance(point, from: start, to: end, origin: origin)
        }
        var maxDist = 0.0
        var maxIdx = 0
        for i in 1..<coords.count - 1 {
            let d = perpDist(coords[i], from: coords[0], to: coords[coords.count - 1])
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }
        if maxDist > toleranceMeters {
            let left = douglasPeucker(Array(coords[0...maxIdx]), toleranceMeters: toleranceMeters)
            let right = douglasPeucker(Array(coords[maxIdx...]), toleranceMeters: toleranceMeters)
            return Array(left.dropLast() + right)
        } else {
            return [coords[0], coords[coords.count - 1]]
        }
    }
}
