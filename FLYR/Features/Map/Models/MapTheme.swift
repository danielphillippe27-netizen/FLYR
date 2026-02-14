import Foundation
import MapboxMaps

/// Helper for loading Mapbox style JSON files from bundle
struct MapTheme {
    /// Get the bundle URL for the first available style JSON file in search order.
    private static func url(forFileNames fileNames: [String]) -> URL? {
        // Try multiple possible bundle subdirectories
        let possiblePaths = [
            "Features/Map/Styles",
            "Styles",
            nil // Root of bundle
        ]
        
        for fileName in fileNames {
            for subdirectory in possiblePaths {
                if let url = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: subdirectory) {
                    return url
                }
            }
        }
        return nil
    }
    
    /// Get style URI for a map mode (fallback to default if JSON not found)
    static func styleURI(for mode: MapMode) -> StyleURI {
        styleURI(for: mode, preferLightStyle: false)
    }

    /// Get style URI for a map mode, optionally using light base for 3D modes (e.g. campaign3D in light view)
    static func styleURI(for mode: MapMode, preferLightStyle: Bool) -> StyleURI {
        let styleCandidates: [String]
        switch mode {
        case .light:
            styleCandidates = ["LightStyle"]
        case .dark:
            styleCandidates = ["DarkStyle"]
        case .black3D:
            styleCandidates = ["BlackWhite3DStyle", "DarkStyle"]
        case .campaign3D:
            // Campaign3DStyle is optional in current app builds.
            // Fall back to base light/dark style JSON before using hosted style URIs.
            styleCandidates = preferLightStyle
                ? ["Campaign3DStyle", "LightStyle", "DarkStyle"]
                : ["Campaign3DStyle", "DarkStyle", "LightStyle"]
        }

        if let url = url(forFileNames: styleCandidates), let styleURI = StyleURI(url: url) {
            return styleURI
        }
        print("ℹ️ [MapTheme] No bundled JSON style found for mode=\(mode.rawValue) candidates=\(styleCandidates.joined(separator: ",")); using hosted style URI")
        
        // Fallback to custom Mapbox styles
        switch mode {
        case .light:
            return lightStyleURI
        case .dark:
            return darkStyleURI
        case .black3D:
            return darkStyleURI
        case .campaign3D:
            // Respect current view: light view → light base; dark view → dark base
            return preferLightStyle ? lightStyleURI : darkStyleURI
        }
    }

    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!
}

