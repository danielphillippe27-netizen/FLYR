import Foundation

/// Map visual mode enum for FLYR map system
enum MapMode: String, CaseIterable {
    case light
    case dark
    case black3D
    case campaign3D
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .black3D: return "3D"
        case .campaign3D: return "Farm"
        }
    }
    
    /// Whether this mode uses 3D building extrusion
    var is3DMode: Bool {
        switch self {
        case .light, .dark:
            return false
        case .black3D, .campaign3D:
            return true
        }
    }
}



