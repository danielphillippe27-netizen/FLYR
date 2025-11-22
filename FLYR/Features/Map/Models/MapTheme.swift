import Foundation
import MapboxMaps

/// Helper for loading Mapbox style JSON files from bundle
struct MapTheme {
    /// Get the bundle URL for a map mode's style JSON file
    static func url(for mode: MapMode) -> URL? {
        let fileName: String
        switch mode {
        case .light:
            fileName = "LightStyle"
        case .dark:
            fileName = "DarkStyle"
        case .black3D:
            fileName = "BlackWhite3DStyle"
        case .campaign3D:
            fileName = "Campaign3DStyle"
        }
        
        // Try multiple possible paths
        let possiblePaths = [
            "Features/Map/Styles",
            "Styles",
            nil // Root of bundle
        ]
        
        for subdirectory in possiblePaths {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: subdirectory) {
                return url
            }
        }
        
        print("⚠️ [MapTheme] Could not find style file: \(fileName).json in bundle")
        return nil
    }
    
    /// Get style URI for a map mode (fallback to default if JSON not found)
    static func styleURI(for mode: MapMode) -> StyleURI {
        // Try to load custom JSON style first
        if let url = url(for: mode), let styleURI = StyleURI(url: url) {
            return styleURI
        }
        
        // Fallback to built-in Mapbox styles
        // These are reliable and always available
        switch mode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .black3D, .campaign3D:
            // Use dark as base for 3D modes (will add 3D layers programmatically)
            return .dark
        }
    }
}

