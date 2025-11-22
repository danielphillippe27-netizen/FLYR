import Foundation

enum Config {
    static var mapboxAccessToken: String {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String else {
            fatalError("❌ Missing Mapbox access token in Info.plist")
        }
        return token
    }
}


