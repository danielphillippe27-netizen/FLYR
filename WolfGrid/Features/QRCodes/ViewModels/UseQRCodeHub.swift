import Foundation
import SwiftUI
import Combine

/// Hook for QR Code Hub navigation state
/// Pure state management - no business logic
@MainActor
class UseQRCodeHub: ObservableObject {
    @Published var selectedDestination: QRCodeDestination?
    
    enum QRCodeDestination: Identifiable {
        case create
        case print
        case analytics
        case mapView
        
        var id: String {
            switch self {
            case .create: return "create"
            case .print: return "print"
            case .analytics: return "analytics"
            case .mapView: return "mapView"
            }
        }
    }
    
    func navigateTo(_ destination: QRCodeDestination) {
        selectedDestination = destination
    }
    
    func clearDestination() {
        selectedDestination = nil
    }
}

