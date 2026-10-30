import Foundation

/// Geometry-only clustering cache. Status, selection, GPS and menu updates do not
/// change the layout; fractional zooms in the same world grid do not either.
struct StandardCampaignClusterLayout {
    struct Point: Equatable {
        let latitude: Double
        let longitude: Double

        var isValid: Bool {
            latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
        }
    }

    struct Cell: Hashable {
        let zoom: Int
        let x: Int
        let y: Int
    }

    struct Plan {
        let clusters: [Cell: [UUID: Point]]
        let individualIDs: Set<UUID>
    }

    private var previousPoints: [UUID: Point]?
    private var previousZoom: Int?
    private(set) var rebuildCount = 0

    static func zoomBucket(_ zoom: Float) -> Int {
        guard zoom.isFinite else { return 0 }
        return Int(floor(min(18, max(0, zoom))))
    }

    mutating func update(points: [UUID: Point], zoom: Float, isMoving: Bool = false) -> Plan? {
        // Google owns the camera animation. Mutating hundreds of overlays while
        // it is drawing the gesture causes visible stalls; apply the latest data at idle.
        guard !isMoving else { return nil }
        let bucket = Self.zoomBucket(zoom)
        guard previousZoom != bucket || previousPoints != points else { return nil }
        previousPoints = points
        previousZoom = bucket
        rebuildCount += 1

        let valid = points.filter { $0.value.isValid }
        guard bucket < 18 else { return Plan(clusters: [:], individualIDs: Set(valid.keys)) }
        let scale = 256 * pow(2, Double(bucket))
        var groups: [Cell: [UUID: Point]] = [:]
        for (id, point) in valid {
            let latitude = min(85.05112878, max(-85.05112878, point.latitude))
            let sine = sin(latitude * .pi / 180)
            let x = (point.longitude + 180) / 360 * scale
            let y = (0.5 - log((1 + sine) / (1 - sine)) / (4 * .pi)) * scale
            let cell = Cell(zoom: bucket, x: Int(floor(x / 64)), y: Int(floor(y / 64)))
            groups[cell, default: [:]][id] = point
        }
        var singles = Set<UUID>()
        var clusters: [Cell: [UUID: Point]] = [:]
        for (cell, members) in groups {
            if members.count == 1 { singles.formUnion(members.keys) }
            else { clusters[cell] = members }
        }
        return Plan(clusters: clusters, individualIDs: singles)
    }
}
