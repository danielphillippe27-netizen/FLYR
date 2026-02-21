import Foundation

enum Config {
    static var mapboxAccessToken: String {
        guard let rawToken = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String else {
            fatalError("❌ Missing Mapbox access token. Set MAPBOX_ACCESS_TOKEN in Config.xcconfig.")
        }

        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty
            || token == "YOUR_MAPBOX_PUBLIC_TOKEN"
            || token == "REPLACE_WITH_YOUR_MAPBOX_PUBLIC_TOKEN"
            || token.hasPrefix("$(") {
            fatalError("❌ Invalid Mapbox access token. Set MAPBOX_ACCESS_TOKEN to a valid public pk.* token in Config.xcconfig.")
        }

        return token
    }
}

