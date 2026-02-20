import Foundation

// MARK: - Secrets Configuration

/// Configuration for API keys and secrets
/// All tokens are read from Info.plist for single source of truth
enum Secrets {
    /// Mapbox access token - stored in Info.plist under MBXAccessToken
    static var mapboxToken: String {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
              !token.isEmpty,
              token != "YOUR_MAPBOX_PUBLIC_TOKEN" else {
            fatalError("❌ Mapbox access token not found in Info.plist. Add MBXAccessToken to your Info.plist.")
        }
        return token
    }
}
