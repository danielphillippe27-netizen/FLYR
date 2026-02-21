import Foundation

struct RouteAssignmentProgress: Equatable, Sendable {
    let completedStops: Int
    let lastStopOrder: Int?
    let lastEventAt: Date?

    static let empty = RouteAssignmentProgress(
        completedStops: 0,
        lastStopOrder: nil,
        lastEventAt: nil
    )

    init(completedStops: Int, lastStopOrder: Int?, lastEventAt: Date?) {
        self.completedStops = max(0, completedStops)
        self.lastStopOrder = lastStopOrder
        self.lastEventAt = lastEventAt
    }

    init(jsonValue: Any?) {
        guard let raw = RouteJSON.dictionary(from: jsonValue) else {
            self = .empty
            return
        }
        let completed = RouteJSON.int(from: RouteJSON.value(in: raw, keys: ["completed_stops", "completedStops"])) ?? 0
        self.init(
            completedStops: completed,
            lastStopOrder: RouteJSON.int(from: RouteJSON.value(in: raw, keys: ["last_stop_order", "lastStopOrder"])),
            lastEventAt: RouteJSON.date(from: RouteJSON.value(in: raw, keys: ["last_event_at", "lastEventAt"]))
        )
    }
}

struct RouteAssignmentSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let routePlanId: UUID
    let name: String
    let status: String
    let totalStops: Int
    let estMinutes: Int?
    let distanceMeters: Int?
    let updatedAt: Date?
    let progress: RouteAssignmentProgress
    let assignedByName: String?

    var completedStops: Int {
        min(max(progress.completedStops, 0), max(totalStops, 0))
    }

    var progressFraction: Double {
        guard totalStops > 0 else { return 0 }
        return Double(completedStops) / Double(totalStops)
    }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    init?(_ json: [String: Any]) {
        guard
            let assignmentId = RouteJSON.uuid(from: RouteJSON.value(in: json, keys: ["assignment_id", "assignmentId", "id"])),
            let routePlanId = RouteJSON.uuid(from: RouteJSON.value(in: json, keys: ["route_plan_id", "routePlanId"]))
        else {
            return nil
        }

        self.id = assignmentId
        self.routePlanId = routePlanId
        self.name = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["name"])) ?? "Route Plan"
        self.status = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["status"])) ?? "assigned"
        self.totalStops = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["total_stops", "totalStops"])) ?? 0
        self.estMinutes = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["est_minutes", "estMinutes"]))
        self.distanceMeters = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["distance_meters", "distanceMeters"]))
        self.updatedAt = RouteJSON.date(from: RouteJSON.value(in: json, keys: ["updated_at", "updatedAt"]))
        self.progress = RouteAssignmentProgress(jsonValue: RouteJSON.value(in: json, keys: ["progress"]))
        self.assignedByName = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["assigned_by_name", "assignedByName"]))
    }
}

struct RoutePlanDetail: Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceId: UUID?
    let campaignId: UUID?
    let name: String
    let totalStops: Int
    let estMinutes: Int?
    let distanceMeters: Int?
    let segments: [RoutePlanSegment]
    let stops: [RoutePlanStop]

    init?(_ json: [String: Any]) {
        let payload: [String: Any]
        if let wrapped = RouteJSON.dictionary(from: RouteJSON.value(in: json, keys: ["get_route_plan_detail", "getRoutePlanDetail", "data", "result"])),
           RouteJSON.value(in: wrapped, keys: ["plan", "route_plan", "routePlan", "stops", "segments"]) != nil {
            payload = wrapped
        } else {
            payload = json
        }

        let routePlanObject = RouteJSON.dictionary(from: RouteJSON.value(in: payload, keys: ["route_plan", "routePlan", "plan"]))

        guard
            let id = RouteJSON.uuid(from: RouteJSON.value(in: payload, keys: ["route_plan_id", "routePlanId", "id"]))
                ?? RouteJSON.uuid(from: RouteJSON.value(in: routePlanObject, keys: ["id"]))
        else {
            return nil
        }

        self.id = id
        self.workspaceId = RouteJSON.uuid(from: RouteJSON.value(in: payload, keys: ["workspace_id", "workspaceId"]))
            ?? RouteJSON.uuid(from: RouteJSON.value(in: routePlanObject, keys: ["workspace_id", "workspaceId"]))
        self.campaignId = RouteJSON.uuid(from: RouteJSON.value(in: payload, keys: ["campaign_id", "campaignId"]))
            ?? RouteJSON.uuid(from: RouteJSON.value(in: routePlanObject, keys: ["campaign_id", "campaignId"]))
        self.name = RouteJSON.string(from: RouteJSON.value(in: payload, keys: ["name"]))
            ?? RouteJSON.string(from: RouteJSON.value(in: routePlanObject, keys: ["name"]))
            ?? "Route Plan"
        self.totalStops = RouteJSON.int(from: RouteJSON.value(in: payload, keys: ["total_stops", "totalStops"]))
            ?? RouteJSON.int(from: RouteJSON.value(in: routePlanObject, keys: ["total_stops", "totalStops"]))
            ?? 0
        self.estMinutes = RouteJSON.int(from: RouteJSON.value(in: payload, keys: ["est_minutes", "estMinutes"]))
            ?? RouteJSON.int(from: RouteJSON.value(in: routePlanObject, keys: ["est_minutes", "estMinutes"]))
        self.distanceMeters = RouteJSON.int(from: RouteJSON.value(in: payload, keys: ["distance_meters", "distanceMeters"]))
            ?? RouteJSON.int(from: RouteJSON.value(in: routePlanObject, keys: ["distance_meters", "distanceMeters"]))

        let rawSegments = RouteJSON.value(in: payload, keys: ["segments"])
            ?? RouteJSON.value(in: routePlanObject, keys: ["segments"])
        let parsedSegments = RouteJSON.dictionaryArray(from: rawSegments)
            .enumerated()
            .map { RoutePlanSegment($0.element, index: $0.offset) }
        self.segments = parsedSegments

        let rawStops = RouteJSON.value(in: payload, keys: ["stops", "ordered_stops", "route_stops"])
        let parsedStops = RouteJSON.dictionaryArray(from: rawStops)
            .enumerated()
            .map { RoutePlanStop($0.element, index: $0.offset) }
            .sorted { $0.stopOrder < $1.stopOrder }
        self.stops = parsedStops
    }
}

struct RoutePlanSegment: Identifiable, Equatable, Sendable {
    let id: String
    let streetName: String
    let side: String
    let fromHouse: Int?
    let toHouse: Int?
    let stopCount: Int
    let color: String?
    let notes: String?

    init(_ json: [String: Any], index: Int) {
        self.streetName = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["street_name", "streetName"])) ?? "Street"
        self.side = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["side"])) ?? "both"
        self.fromHouse = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["from_house", "fromHouse"]))
        self.toHouse = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["to_house", "toHouse"]))
        self.stopCount = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["stop_count", "stopCount"])) ?? 0
        self.color = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["color"]))
        self.notes = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["notes"]))

        let fallback = "\(streetName)-\(side)-\(fromHouse ?? -1)-\(toHouse ?? -1)-\(index)"
        self.id = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["id"])) ?? fallback
    }
}

struct RoutePlanStop: Identifiable, Equatable, Sendable {
    let id: String
    let stopOrder: Int
    let addressId: UUID?
    let gersId: String?
    let latitude: Double?
    let longitude: Double?
    let displayAddress: String
    let buildingId: UUID?

    init(_ json: [String: Any], index: Int) {
        let stopOrder = RouteJSON.int(from: RouteJSON.value(in: json, keys: ["stop_order", "stopOrder", "order"])) ?? (index + 1)
        let addressId = RouteJSON.uuid(from: RouteJSON.value(in: json, keys: ["address_id", "addressId"]))
        let gersId = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["gers_id", "gersId"]))
        let displayAddress = RouteJSON.string(from: RouteJSON.value(in: json, keys: ["display_address", "displayAddress", "address", "formatted"]))
            ?? "Stop \(stopOrder)"

        self.stopOrder = stopOrder
        self.addressId = addressId
        self.gersId = gersId
        self.latitude = RouteJSON.double(from: RouteJSON.value(in: json, keys: ["lat", "latitude"]))
        self.longitude = RouteJSON.double(from: RouteJSON.value(in: json, keys: ["lng", "lon", "longitude"]))
        self.displayAddress = displayAddress
        self.buildingId = RouteJSON.uuid(from: RouteJSON.value(in: json, keys: ["building_id", "buildingId"]))

        let idBase = addressId?.uuidString ?? gersId ?? "stop-\(stopOrder)"
        self.id = "\(idBase)-\(stopOrder)"
    }
}

enum RouteJSON {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func rows(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let rows = object as? [[String: Any]] {
            return rows
        }
        if let row = object as? [String: Any] {
            return [row]
        }
        return []
    }

    static func value(in object: [String: Any]?, keys: [String]) -> Any? {
        guard let object else { return nil }
        for key in keys {
            if let value = object[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    static func string(from value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return String(double)
        }
        return nil
    }

    static func int(from value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let int = Int(trimmed) {
                return int
            }
            if let double = Double(trimmed) {
                return Int(double)
            }
        }
        return nil
    }

    static func double(from value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func uuid(from value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }
        if let string = string(from: value) {
            return UUID(uuidString: string)
        }
        return nil
    }

    static func date(from value: Any?) -> Date? {
        guard let string = string(from: value) else {
            return nil
        }
        if let date = isoWithFractional.date(from: string) {
            return date
        }
        return isoBasic.date(from: string)
    }

    static func dictionary(from value: Any?) -> [String: Any]? {
        guard let value, !(value is NSNull) else { return nil }
        if let dict = value as? [String: Any] {
            return dict
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return nil
    }

    static func dictionaryArray(from value: Any?) -> [[String: Any]] {
        guard let value, !(value is NSNull) else { return [] }
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return dictionaryArray(from: object)
        }
        return []
    }
}
