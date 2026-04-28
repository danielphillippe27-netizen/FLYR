import Foundation

struct FarmExecutionContext: Equatable, Sendable {
    let farmId: UUID
    let farmName: String
    let touchId: UUID
    let touchTitle: String
    let touchDate: Date
    let touchType: FarmTouchType
    let campaignId: UUID
    let cycleNumber: Int?
    let cycleName: String?

    var sessionMode: SessionMode {
        switch touchType {
        case .flyer, .newsletter, .ad:
            return .flyer
        case .doorKnock, .event, .custom:
            return .doorKnocking
        }
    }
}
