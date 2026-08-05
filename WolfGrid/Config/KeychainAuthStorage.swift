import Foundation
import Security

/// Keychain storage for Supabase session tokens and AppUser profile.
/// Service: com.wolfgrid.auth
enum KeychainAuthStorage {
    private static let service = "com.wolfgrid.auth"
    private static let legacyService = "com.flyr.auth"
    private static let sessionAccessKey = "supabase_access_token"
    private static let sessionRefreshKey = "supabase_refresh_token"
    private static let appUserKey = "app_user"
    private static let authProviderKey = "auth_provider"
    private static let appleIdTokenKey = "apple_id_token"

    // MARK: - Session

    static func saveSession(accessToken: String, refreshToken: String) {
        save(string: accessToken, key: sessionAccessKey)
        save(string: refreshToken, key: sessionRefreshKey)
    }

    static func loadSession() -> (accessToken: String, refreshToken: String)? {
        guard let access = loadString(key: sessionAccessKey),
              let refresh = loadString(key: sessionRefreshKey) else {
            return nil
        }
        return (access, refresh)
    }

    static func deleteSession() {
        delete(key: sessionAccessKey)
        delete(key: sessionRefreshKey)
    }

    // MARK: - Identity token (for backend auth: Apple / Google)

    enum AuthProvider: String {
        case apple
        case google
        case email
    }

    static func saveAuthProvider(_ provider: AuthProvider) {
        save(string: provider.rawValue, key: authProviderKey)
    }

    static func loadAuthProvider() -> AuthProvider? {
        loadString(key: authProviderKey).flatMap { AuthProvider(rawValue: $0) }
    }

    static func saveAppleIdToken(_ token: String) {
        save(string: token, key: appleIdTokenKey)
    }

    static func loadAppleIdToken() -> String? {
        loadString(key: appleIdTokenKey)
    }

    static func deleteIdentityTokens() {
        delete(key: authProviderKey)
        delete(key: appleIdTokenKey)
    }

    // MARK: - AppUser

    static func saveAppUser(_ user: AppUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        save(data: data, key: appUserKey)
    }

    static func loadAppUser() -> AppUser? {
        guard let data = loadData(key: appUserKey),
              let user = try? JSONDecoder().decode(AppUser.self, from: data) else {
            return nil
        }
        return user
    }

    static func deleteAppUser() {
        delete(key: appUserKey)
    }

    static func clearAll() {
        deleteSession()
        deleteAppUser()
        deleteIdentityTokens()
        deleteWebhookURL()
    }

    // MARK: - Webhook URL

    private static let webhookURLKey = "leads_webhook_url"

    static func saveWebhookURL(_ url: String) {
        save(string: url, key: webhookURLKey)
    }

    static func loadWebhookURL() -> String? {
        loadString(key: webhookURLKey)
    }

    static func deleteWebhookURL() {
        delete(key: webhookURLKey)
    }

    // MARK: - Helpers

    private static func save(string: String, key: String) {
        guard let data = string.data(using: .utf8) else { return }
        save(data: data, key: key)
    }

    private static func save(data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary) // Remove existing so we can add
        SecItemAdd(query as CFDictionary, nil)
        delete(key: key, service: legacyService)
    }

    private static func loadString(key: String) -> String? {
        loadData(key: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func loadData(key: String) -> Data? {
        if let data = loadData(key: key, service: service) {
            return data
        }
        if let legacyData = loadData(key: key, service: legacyService) {
            save(data: legacyData, key: key)
            delete(key: key, service: legacyService)
            return legacyData
        }
        return nil
    }

    private static func loadData(key: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func delete(key: String) {
        delete(key: key, service: service)
        delete(key: key, service: legacyService)
    }

    private static func delete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
