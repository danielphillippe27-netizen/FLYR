import SwiftUI

enum HomeSection: Int, CaseIterable, Identifiable {
    case flyr, campaigns, farm
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .flyr: "FLYR"
        case .campaigns: "Campaigns"
        case .farm: "Farm"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .flyr: "FLYR"
        case .campaigns: "Campaigns"
        case .farm: "Farm"
        }
    }
}




