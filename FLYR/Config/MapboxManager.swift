import Foundation

/// Manages Mapbox configuration and access tokens
class MapboxManager {
    static let shared = MapboxManager()
    
    let accessToken: String
    
    private init() {
        // Use bundle info dictionary (same plist used for Debug and Release; avoid file-path reads)
        let token = (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String)
        guard let token = token, !token.isEmpty else {
            fatalError("Mapbox access token not found in Info.plist (MBXAccessToken or MapboxAccessToken)")
        }
        self.accessToken = token
    }
}







