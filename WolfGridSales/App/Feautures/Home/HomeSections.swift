import SwiftUI

enum HomeSection: Int, CaseIterable, Identifiable {
    case wolfgrid, campaigns
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .wolfgrid: "WolfGrid"
        case .campaigns: "Campaign"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .wolfgrid: "WolfGrid"
        case .campaigns: "Campaign"
        }
    }
}

