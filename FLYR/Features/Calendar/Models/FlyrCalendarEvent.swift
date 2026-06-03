import Foundation
import CryptoKit
import SwiftUI

struct FlyrCalendarEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var userId: UUID?
    var workspaceId: UUID?
    var title: String
    var startAt: Date
    var endAt: Date
    var isAllDay: Bool
    var eventType: String
    var contactId: UUID?
    var contactName: String?
    var contactAddress: String?
    var campaignId: UUID?
    var campaignName: String?
    var recurrenceRule: String
    var recurrenceUntil: Date?
    var sourceKind: String?
    var sourceId: UUID?
    var notes: String?
    var location: String?
    var colorKey: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case eventType = "event_type"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case contactAddress = "contact_address"
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case recurrenceRule = "recurrence_rule"
        case recurrenceUntil = "recurrence_until"
        case sourceKind = "source_kind"
        case sourceId = "source_id"
        case notes
        case location
        case colorKey = "color_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        workspaceId = try container.decodeIfPresent(UUID.self, forKey: .workspaceId)
        title = try container.decode(String.self, forKey: .title)
        startAt = try container.decode(Date.self, forKey: .startAt)
        endAt = try container.decode(Date.self, forKey: .endAt)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType) ?? FlyrCalendarEventType.appointment.rawValue
        contactId = try container.decodeIfPresent(UUID.self, forKey: .contactId)
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName)
        contactAddress = try container.decodeIfPresent(String.self, forKey: .contactAddress)
        campaignId = try container.decodeIfPresent(UUID.self, forKey: .campaignId)
        campaignName = try container.decodeIfPresent(String.self, forKey: .campaignName)
        recurrenceRule = try container.decodeIfPresent(String.self, forKey: .recurrenceRule) ?? CalendarRecurrenceRule.none.rawValue
        recurrenceUntil = try container.decodeIfPresent(Date.self, forKey: .recurrenceUntil)
        sourceKind = try container.decodeIfPresent(String.self, forKey: .sourceKind)
        sourceId = try container.decodeIfPresent(UUID.self, forKey: .sourceId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        colorKey = try container.decodeIfPresent(String.self, forKey: .colorKey) ?? "red"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        workspaceId: UUID? = nil,
        title: String,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool = false,
        eventType: String = FlyrCalendarEventType.appointment.rawValue,
        contactId: UUID? = nil,
        contactName: String? = nil,
        contactAddress: String? = nil,
        campaignId: UUID? = nil,
        campaignName: String? = nil,
        recurrenceRule: String = CalendarRecurrenceRule.none.rawValue,
        recurrenceUntil: Date? = nil,
        sourceKind: String? = nil,
        sourceId: UUID? = nil,
        notes: String? = nil,
        location: String? = nil,
        colorKey: String = "red",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.workspaceId = workspaceId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.eventType = eventType
        self.contactId = contactId
        self.contactName = contactName
        self.contactAddress = contactAddress
        self.campaignId = campaignId
        self.campaignName = campaignName
        self.recurrenceRule = recurrenceRule
        self.recurrenceUntil = recurrenceUntil
        self.sourceKind = sourceKind
        self.sourceId = sourceId
        self.notes = notes
        self.location = location
        self.colorKey = colorKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    static func linkedId(sourceKind: String, sourceId: UUID, eventType: FlyrCalendarEventType) -> UUID {
        let seed = "flyr-calendar-event|\(sourceKind)|\(sourceId.uuidString.lowercased())|\(eventType.rawValue)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum FlyrCalendarEventType: String, CaseIterable, Identifiable, Codable, Sendable {
    case appointment
    case doorKnock = "door_knock"
    case followUp = "follow_up"
    case showing
    case call
    case task
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appointment: return "Appointment"
        case .doorKnock: return "Door Knock"
        case .followUp: return "Follow-Up"
        case .showing: return "Showing"
        case .call: return "Call"
        case .task: return "Task"
        case .personal: return "Personal"
        }
    }

    var symbol: String {
        switch self {
        case .appointment: return "calendar.badge.clock"
        case .doorKnock: return "figure.walk"
        case .followUp: return "arrow.uturn.forward"
        case .showing: return "house"
        case .call: return "phone"
        case .task: return "checklist"
        case .personal: return "person"
        }
    }

    var defaultColorKey: String {
        switch self {
        case .appointment: return "yellow"
        case .doorKnock: return "green"
        case .followUp: return "yellow"
        case .showing: return "green"
        case .call: return "purple"
        case .task: return "yellow"
        case .personal: return "gray"
        }
    }

    func defaultTitle(contactName: String?) -> String {
        defaultTitle(contactName: contactName, campaignName: nil)
    }

    func defaultTitle(contactName: String?, campaignName: String?) -> String {
        if let campaignName, !campaignName.isEmpty {
            return "\(title): \(campaignName)"
        }
        if let contactName, !contactName.isEmpty {
            return "\(title): \(contactName)"
        }
        return title
    }
}

enum CalendarRecurrenceRule: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Does Not Repeat"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var component: Calendar.Component? {
        switch self {
        case .none: return nil
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }
}

enum CalendarItemKind: String, Sendable {
    case standalone
    case reminder
    case meeting
    case session
}

enum CalendarEventSourceKind: String, Sendable {
    case contactAppointment = "contact_appointment"
    case contactFollowUp = "contact_follow_up"
    case session
}

struct CalendarItem: Identifiable, Equatable, Sendable {
    let id: String
    let sourceId: UUID
    let kind: CalendarItemKind
    let eventType: String
    let title: String
    let startAt: Date
    let endAt: Date
    let isAllDay: Bool
    let notes: String?
    let location: String?
    let colorKey: String
    let contactName: String?
    let contactId: UUID?
    let campaignName: String?
    let campaignId: UUID?
    let address: String?

    init(
        id: String,
        sourceId: UUID,
        kind: CalendarItemKind,
        eventType: String,
        title: String,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool,
        notes: String?,
        location: String?,
        colorKey: String,
        contactName: String?,
        contactId: UUID?,
        campaignName: String? = nil,
        campaignId: UUID? = nil,
        address: String?
    ) {
        self.id = id
        self.sourceId = sourceId
        self.kind = kind
        self.eventType = eventType
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.notes = notes
        self.location = location
        self.colorKey = colorKey
        self.contactName = contactName
        self.contactId = contactId
        self.campaignName = campaignName
        self.campaignId = campaignId
        self.address = address
    }

    var searchHaystack: String {
        [
            title,
            notes ?? "",
            location ?? "",
            contactName ?? "",
            campaignName ?? "",
            address ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

extension CalendarItem {
    init(event: FlyrCalendarEvent) {
        self.init(
            id: "event-\(event.id.uuidString)",
            sourceId: event.id,
            kind: .standalone,
            eventType: event.eventType,
            title: event.title,
            startAt: event.startAt,
            endAt: event.endAt,
            isAllDay: event.isAllDay,
            notes: event.notes,
            location: event.location,
            colorKey: event.colorKey,
            contactName: event.contactName,
            contactId: event.contactId,
            campaignName: event.campaignName,
            campaignId: event.campaignId,
            address: event.contactAddress ?? event.location
        )
    }

    init?(session: SessionRecord) {
        guard let sessionId = session.id else { return nil }

        let duration = max(60, session.durationSeconds)
        let resolvedEnd = session.end_time ?? session.start_time.addingTimeInterval(duration)
        let endAt = max(resolvedEnd, session.start_time.addingTimeInterval(60))
        let sessionMode = session.sessionModeValue
        let title = session.end_time == nil ? "\(sessionMode.displayName) Active" : sessionMode.displayName

        var details: [String] = []
        let doors = session.doorsCount
        let conversations = max(0, session.conversations ?? 0)
        let leads = session.leadsCreated
        let appointments = session.appointmentsCount
        if doors > 0 { details.append("\(doors) homes") }
        if conversations > 0 { details.append("\(conversations) conv") }
        if leads > 0 { details.append("\(leads) leads") }
        if appointments > 0 { details.append("\(appointments) appts") }
        if session.distance_meters ?? 0 > 0 {
            details.append(String(format: "%.1f km", (session.distance_meters ?? 0) / 1000))
        }
        if details.isEmpty {
            let minutes = max(1, Int(duration / 60))
            details.append("\(minutes) min")
        }

        self.init(
            id: "session-\(sessionId.uuidString)",
            sourceId: sessionId,
            kind: .session,
            eventType: FlyrCalendarEventType.doorKnock.rawValue,
            title: title,
            startAt: session.start_time,
            endAt: endAt,
            isAllDay: false,
            notes: session.notes,
            location: nil,
            colorKey: sessionMode == .flyer ? CalendarColorKey.blue.rawValue : CalendarColorKey.green.rawValue,
            contactName: nil,
            contactId: nil,
            campaignName: nil,
            campaignId: session.campaign_id,
            address: details.joined(separator: " • ")
        )
    }
}

enum CalendarColorKey: String, CaseIterable, Identifiable {
    case red
    case blue
    case green
    case yellow
    case purple
    case pink
    case gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return Color(red: 1, green: 0.23, blue: 0.19)
        case .blue: return Color(red: 0.04, green: 0.52, blue: 1)
        case .green: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .yellow: return Color(red: 1, green: 0.8, blue: 0.12)
        case .purple: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .pink: return Color(red: 1, green: 0.22, blue: 0.45)
        case .gray: return Color(uiColor: .systemGray)
        }
    }

    static func color(for key: String) -> Color {
        CalendarColorKey(rawValue: key)?.color ?? CalendarColorKey.red.color
    }
}
