import Foundation

/// Goal type for session tracking
enum GoalType: String, Codable, CaseIterable {
    case flyers
    case knocks
    case conversations
    case leads
    case appointments

    var displayName: String {
        switch self {
        case .flyers: return "Flyers"
        case .knocks: return "Door Knock"
        case .conversations: return "Conversations"
        case .leads: return "Leads"
        case .appointments: return "Appointments"
        }
    }

    /// Goal types shown in the Start Session dropdown (excludes legacy knocks)
    static var goalPickerCases: [GoalType] {
        [.flyers, .conversations, .leads, .appointments]
    }
}


