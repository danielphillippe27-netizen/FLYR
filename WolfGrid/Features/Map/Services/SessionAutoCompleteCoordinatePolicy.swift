import CoreLocation

enum SessionAutoCompleteCoordinatePolicy {
    /// Only restore coordinates belonging to this session's saved target list.
    static func merge(targetIDs: [String], incoming: [String: CLLocationCoordinate2D], into existing: inout [String: CLLocation]) -> Bool {
        let active = Set(targetIDs.map { $0.lowercased() })
        var changed = false
        for (id, coordinate) in incoming {
            let key = id.lowercased()
            guard active.contains(key), CLLocationCoordinate2DIsValid(coordinate) else { continue }
            if let previous = existing[key], previous.coordinate.latitude == coordinate.latitude,
               previous.coordinate.longitude == coordinate.longitude { continue }
            existing[key] = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            changed = true
        }
        return changed
    }
}
