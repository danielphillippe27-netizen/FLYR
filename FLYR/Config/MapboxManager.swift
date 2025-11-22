import Foundation

/// Manages Mapbox configuration and access tokens
class MapboxManager {
    static let shared = MapboxManager()
    
    let accessToken: String
    
    private init() {
        // Read from Info.plist
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let token = plist["MBXAccessToken"] as? String else {
            fatalError("Mapbox access token not found in Info.plist")
        }
        self.accessToken = token
    }
}







