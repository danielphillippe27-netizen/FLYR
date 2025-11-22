import Foundation
import MapboxMaps

enum MapStyle: String, CaseIterable, Identifiable {
    case standard    // full road labels + POIs
    case dark        // black minimal
    case light       // clean light mode
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .standard: return "Standard"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    
    var iconName: String {
        switch self {
        case .standard: return "paintbrush.fill"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
    
    var mapboxStyleURI: StyleURI {
        switch self {
        case .standard:
            return .streets  // Full labeled streets, POIs, parks
        case .dark:
            return .dark     // Dark minimal style
        case .light:
            return .light    // Clean light mode
        }
    }
}


