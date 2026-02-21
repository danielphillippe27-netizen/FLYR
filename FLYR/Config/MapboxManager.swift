import Foundation

/// Manages Mapbox configuration and access tokens
class MapboxManager {
    static let shared = MapboxManager()
    
    let accessToken: String
    
    private init() {
        self.accessToken = Config.mapboxAccessToken
    }
}






