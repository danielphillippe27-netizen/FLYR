import Foundation
import MapboxMaps

enum MapStyle: String, CaseIterable, Identifiable {
    case dark        // custom dark style
    case light       // custom light style
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    
    var iconName: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
    
    var mapboxStyleURI: StyleURI {
        switch self {
        case .dark:
            // Custom dark style: mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19
            return StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!
        case .light:
            // Custom light style: mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4
            return StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
        }
    }
}


