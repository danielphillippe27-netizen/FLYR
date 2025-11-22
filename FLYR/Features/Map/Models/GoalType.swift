import Foundation

/// Goal type for session tracking
enum GoalType: String, Codable {
    case flyers
    case knocks
    
    var displayName: String {
        switch self {
        case .flyers: return "Flyers"
        case .knocks: return "Door Knocks"
        }
    }
}


