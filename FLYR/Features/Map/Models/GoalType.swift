import Foundation

/// Goal type for session tracking
enum GoalType: String, Codable, CaseIterable, Identifiable {
    case flyers
    case knocks
    case conversations
    case leads
    case appointments
    case time

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flyers: return "Flyers"
        case .knocks: return "Homes"
        case .conversations: return "Conversations"
        case .leads: return "Leads"
        case .appointments: return "Appointment"
        case .time: return "Time"
        }
    }

    var pickerTitle: String {
        switch self {
        case .knocks:
            return "Hit homes"
        case .conversations:
            return "Have conversations"
        case .appointments:
            return "Get an appointment"
        case .time:
            return "Work for time"
        case .flyers:
            return "Flyers"
        case .leads:
            return "Leads"
        }
    }

    var pickerSubtitle: String {
        switch self {
        case .knocks:
            return "Stop once you've covered enough houses."
        case .conversations:
            return "Track progress by live conversations."
        case .appointments:
            return "Treat one booked appointment as the win."
        case .time:
            return "Run the session for a set amount of minutes."
        case .flyers:
            return "Legacy flyer goal."
        case .leads:
            return "Legacy lead goal."
        }
    }

    var pillLabel: String {
        switch self {
        case .conversations:
            return "Convos"
        default:
            return displayName
        }
    }

    var metricLabel: String {
        switch self {
        case .flyers:
            return "flyers"
        case .knocks:
            return "homes"
        case .conversations:
            return "conversations"
        case .leads:
            return "leads"
        case .appointments:
            return "appointments"
        case .time:
            return "min"
        }
    }

    var progressMetricLabel: String {
        switch self {
        case .knocks:
            return "doors"
        default:
            return metricLabel
        }
    }

    var allowsGoalAmountEditing: Bool {
        fixedGoalAmount == nil
    }

    var fixedGoalAmount: Int? {
        switch self {
        case .appointments:
            return 1
        default:
            return nil
        }
    }

    func minimumAmount(for mode: SessionMode) -> Int {
        switch self {
        case .time:
            return 15
        case .appointments:
            return 1
        default:
            return 1
        }
    }

    func maximumAmount(for mode: SessionMode, targetCount: Int) -> Int {
        switch self {
        case .time:
            return 240
        case .appointments:
            return 1
        default:
            return max(1, targetCount)
        }
    }

    func defaultAmount(for mode: SessionMode, targetCount: Int) -> Int {
        switch self {
        case .knocks:
            return min(max(1, targetCount), 25)
        case .conversations:
            return min(max(1, targetCount), 10)
        case .appointments:
            return 1
        case .time:
            return 60
        case .flyers:
            return min(max(1, targetCount), 25)
        case .leads:
            return min(max(1, targetCount), 5)
        }
    }

    func normalizedAmount(_ amount: Int, for mode: SessionMode, targetCount: Int) -> Int {
        let minAmount = minimumAmount(for: mode)
        let maxAmount = maximumAmount(for: mode, targetCount: targetCount)
        return min(max(minAmount, fixedGoalAmount ?? amount), maxAmount)
    }

    func formattedGoalAmount(_ amount: Int) -> String {
        switch self {
        case .flyers:
            return "\(amount) flyer\(amount == 1 ? "" : "s")"
        case .knocks:
            return "\(amount) home\(amount == 1 ? "" : "s")"
        case .conversations:
            return "\(amount) conversation\(amount == 1 ? "" : "s")"
        case .leads:
            return "\(amount) lead\(amount == 1 ? "" : "s")"
        case .appointments:
            return "\(amount) appointment\(amount == 1 ? "" : "s")"
        case .time:
            return "\(amount) min"
        }
    }

    func goalLabelText(amount: Int) -> String {
        switch self {
        case .appointments:
            return "Goal: get an appointment"
        default:
            return "Goal: \(formattedGoalAmount(amount))"
        }
    }

    static func goalPickerCases(for mode: SessionMode) -> [GoalType] {
        switch mode {
        case .doorKnocking:
            return [.knocks, .conversations, .appointments]
        case .flyer:
            return [.time]
        }
    }
}
