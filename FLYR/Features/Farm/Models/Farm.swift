import Foundation
import CoreLocation

/// Farm model representing a geographic farming territory
struct Farm: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let userId: UUID
    let workspaceId: UUID?
    let name: String
    let description: String?
    let polygon: String? // GeoJSON string from PostGIS
    let startDate: Date
    let endDate: Date
    let frequency: Int // touches per month (1-4)
    let createdAt: Date
    let updatedAt: Date?
    let areaLabel: String? // Optional area label/description
    let isActiveFlag: Bool?
    let touchesPerInterval: Int?
    let touchesInterval: String?
    let goalType: String?
    let goalTarget: Int?
    let cycleCompletionWindowDays: Int?
    let touchTypes: [String]?
    let annualBudgetCents: Int?
    let homeLimit: Int?
    let addressCount: Int?
    let lastGeneratedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "owner_id"
        case workspaceId = "workspace_id"
        case name
        case description
        case polygon
        case startDate = "start_date"
        case endDate = "end_date"
        case frequency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case areaLabel = "area_label"
        case isActiveFlag = "is_active"
        case touchesPerInterval = "touches_per_interval"
        case touchesInterval = "touches_interval"
        case goalType = "goal_type"
        case goalTarget = "goal_target"
        case cycleCompletionWindowDays = "cycle_completion_window_days"
        case touchTypes = "touch_types"
        case annualBudgetCents = "annual_budget_cents"
        case homeLimit = "home_limit"
        case addressCount = "address_count"
        case lastGeneratedAt = "last_generated_at"
    }
    
    /// Convert polygon GeoJSON string to CLLocationCoordinate2D array
    /// Handles both GeoJSON Feature and raw Geometry formats
    var polygonCoordinates: [CLLocationCoordinate2D]? {
        guard let polygon = polygon else { return nil }
        
        // Try to parse as JSON
        guard let data = polygon.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Handle GeoJSON Feature format
        if let geometry = json["geometry"] as? [String: Any],
           let type = geometry["type"] as? String,
           type == "Polygon",
           let coordinates = geometry["coordinates"] as? [[[Double]]],
           let firstRing = coordinates.first {
            return firstRing.compactMap { coord in
                guard coord.count >= 2 else { return nil }
                return CLLocationCoordinate2D(
                    latitude: coord[1],
                    longitude: coord[0]
                )
            }
        }
        
        // Handle raw Geometry format
        if let type = json["type"] as? String,
           type == "Polygon",
           let coordinates = json["coordinates"] as? [[[Double]]],
           let firstRing = coordinates.first {
            return firstRing.compactMap { coord in
                guard coord.count >= 2 else { return nil }
                return CLLocationCoordinate2D(
                    latitude: coord[1],
                    longitude: coord[0]
                )
            }
        }
        
        return nil
    }
    
    /// Check if farm is currently active
    var isActive: Bool {
        if let isActiveFlag {
            return isActiveFlag && !isCompleted
        }
        let now = Date()
        return now >= startDate && now <= endDate
    }
    
    /// Check if farm is completed
    var isCompleted: Bool {
        Date() > endDate
    }
    
    /// Calculate progress percentage (0.0 - 1.0)
    var progress: Double {
        let now = Date()
        guard now >= startDate && endDate > startDate else {
            return now < startDate ? 0.0 : 1.0
        }
        
        let totalDuration = endDate.timeIntervalSince(startDate)
        let elapsed = now.timeIntervalSince(startDate)
        return min(max(elapsed / totalDuration, 0.0), 1.0)
    }
}

/// Database row representation for farms
struct FarmDBRow: Codable {
    let id: UUID
    let ownerId: UUID
    let workspaceId: UUID?
    let name: String
    let description: String?
    let polygon: String? // PostGIS returns as GeoJSON
    let startDate: Date
    let endDate: Date
    let frequency: Int
    let createdAt: Date
    let updatedAt: Date?
    let areaLabel: String?
    let isActiveFlag: Bool?
    let touchesPerInterval: Int?
    let touchesInterval: String?
    let goalType: String?
    let goalTarget: Int?
    let cycleCompletionWindowDays: Int?
    let touchTypes: [String]?
    let annualBudgetCents: Int?
    let homeLimit: Int?
    let addressCount: Int?
    let lastGeneratedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case workspaceId = "workspace_id"
        case name
        case description
        case polygon
        case startDate = "start_date"
        case endDate = "end_date"
        case frequency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case areaLabel = "area_label"
        case isActiveFlag = "is_active"
        case touchesPerInterval = "touches_per_interval"
        case touchesInterval = "touches_interval"
        case goalType = "goal_type"
        case goalTarget = "goal_target"
        case cycleCompletionWindowDays = "cycle_completion_window_days"
        case touchTypes = "touch_types"
        case annualBudgetCents = "annual_budget_cents"
        case homeLimit = "home_limit"
        case addressCount = "address_count"
        case lastGeneratedAt = "last_generated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        workspaceId = try container.decodeIfPresent(UUID.self, forKey: .workspaceId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        polygon = try container.decodeIfPresent(String.self, forKey: .polygon)
        startDate = try Self.decodeDate(for: .startDate, in: container)
        endDate = try Self.decodeDate(for: .endDate, in: container)
        frequency = try container.decode(Int.self, forKey: .frequency)
        createdAt = try Self.decodeDate(for: .createdAt, in: container)
        updatedAt = try Self.decodeOptionalDate(for: .updatedAt, in: container)
        areaLabel = try container.decodeIfPresent(String.self, forKey: .areaLabel)
        isActiveFlag = try container.decodeIfPresent(Bool.self, forKey: .isActiveFlag)
        touchesPerInterval = try container.decodeIfPresent(Int.self, forKey: .touchesPerInterval)
        touchesInterval = try container.decodeIfPresent(String.self, forKey: .touchesInterval)
        goalType = try container.decodeIfPresent(String.self, forKey: .goalType)
        goalTarget = try container.decodeIfPresent(Int.self, forKey: .goalTarget)
        cycleCompletionWindowDays = try container.decodeIfPresent(Int.self, forKey: .cycleCompletionWindowDays)
        touchTypes = try container.decodeIfPresent([String].self, forKey: .touchTypes)
        annualBudgetCents = try container.decodeIfPresent(Int.self, forKey: .annualBudgetCents)
        homeLimit = try container.decodeIfPresent(Int.self, forKey: .homeLimit)
        addressCount = try container.decodeIfPresent(Int.self, forKey: .addressCount)
        lastGeneratedAt = try Self.decodeOptionalDate(for: .lastGeneratedAt, in: container)
    }

    private static func decodeDate(
        for key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        if let dateString = try? container.decode(String.self, forKey: key),
           let parsedDate = parseDate(dateString) {
            return parsedDate
        }
        return try container.decode(Date.self, forKey: key)
    }

    private static func decodeOptionalDate(
        for key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date? {
        guard let dateString = try container.decodeIfPresent(String.self, forKey: key) else {
            return try container.decodeIfPresent(Date.self, forKey: key)
        }
        return parseDate(dateString)
    }

    private static func parseDate(_ value: String) -> Date? {
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let dateOnly = dateOnlyFormatter.date(from: value) {
            return dateOnly
        }

        let isoWithFractionalSeconds = ISO8601DateFormatter()
        isoWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractionalSeconds.date(from: value) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: value)
    }
    
    func toFarm() -> Farm {
        Farm(
            id: id,
            userId: ownerId,
            workspaceId: workspaceId,
            name: name,
            description: description,
            polygon: polygon,
            startDate: startDate,
            endDate: endDate,
            frequency: frequency,
            createdAt: createdAt,
            updatedAt: updatedAt,
            areaLabel: areaLabel,
            isActiveFlag: isActiveFlag,
            touchesPerInterval: touchesPerInterval,
            touchesInterval: touchesInterval,
            goalType: goalType,
            goalTarget: goalTarget,
            cycleCompletionWindowDays: cycleCompletionWindowDays,
            touchTypes: touchTypes,
            annualBudgetCents: annualBudgetCents,
            homeLimit: homeLimit,
            addressCount: addressCount,
            lastGeneratedAt: lastGeneratedAt
        )
    }
}
