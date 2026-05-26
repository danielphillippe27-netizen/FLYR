import SwiftUI

enum HomeSection: Int, CaseIterable, Identifiable {
    case flyr, campaigns
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .flyr: "FLYR"
        case .campaigns: "Campaign"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .flyr: "FLYR"
        case .campaigns: "Campaign"
        }
    }
}


