import Foundation

// MARK: - Activity Type

enum ActivityType: String, Codable, CaseIterable {
    case knock = "knock"
    case call = "call"
    case flyer = "flyer"
    case note = "note"
    case text = "text"
    case email = "email"
    case meeting = "meeting"
    
    var displayName: String {
        switch self {
        case .knock: return "Door Knock"
        case .call: return "Call"
        case .flyer: return "Flyer"
        case .note: return "Note"
        case .text: return "Text"
        case .email: return "Email"
        case .meeting: return "Meeting"
        }
    }
    
    var icon: String {
        switch self {
        case .knock: return "hand.raised.fill"
        case .call: return "phone.fill"
        case .flyer: return "doc.fill"
        case .note: return "note.text"
        case .text: return "message.fill"
        case .email: return "envelope.fill"
        case .meeting: return "calendar"
        }
    }
}

// MARK: - Contact Activity

struct ContactActivity: Codable, Identifiable, Equatable {
    let id: UUID
    let contactId: UUID
    let type: ActivityType
    let note: String?
    let timestamp: Date
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "contact_id"
        case type
        case note
        case timestamp
        case createdAt = "created_at"
    }
    
    init(
        id: UUID = UUID(),
        contactId: UUID,
        type: ActivityType,
        note: String? = nil,
        timestamp: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contactId = contactId
        self.type = type
        self.note = note
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}

// MARK: - Contact Activity Extensions

extension ContactActivity {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var displayText: String {
        if let note = note, !note.isEmpty {
            return note
        }
        return type.displayName
    }
}

// MARK: - Preview Helpers

extension ContactActivity {
    static let mockActivities: [ContactActivity] = [
        ContactActivity(
            contactId: UUID(),
            type: .knock,
            note: "Spoke with owner",
            timestamp: Date().addingTimeInterval(-86400 * 3)
        ),
        ContactActivity(
            contactId: UUID(),
            type: .flyer,
            note: "Left flyer",
            timestamp: Date().addingTimeInterval(-86400 * 10)
        ),
        ContactActivity(
            contactId: UUID(),
            type: .call,
            note: "Follow-up call",
            timestamp: Date().addingTimeInterval(-86400 * 5)
        )
    ]
}





