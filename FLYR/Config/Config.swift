import Foundation

enum Config {
    private static let dialerEnabledWorkspaceIDsKey = "DIALER_ENABLED_WORKSPACE_IDS"
    private static let dialerEnabledEmailsKey = "DIALER_ENABLED_EMAILS"

    private static func stringValue(for key: String) -> String? {
        let rawValue = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue,
              !rawValue.isEmpty,
              !rawValue.hasPrefix("$(") else {
            return nil
        }
        return rawValue
    }

    private static func urlValue(for key: String) -> URL? {
        guard let value = stringValue(for: key) else { return nil }
        return URL(string: value)
    }

    private static func uuidListValue(for key: String) -> [UUID] {
        guard let rawValue = stringValue(for: key) else { return [] }

        return rawValue
            .split(separator: ",")
            .compactMap { value in
                UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    private static func normalizedStringListValue(for key: String) -> [String] {
        guard let rawValue = stringValue(for: key) else { return [] }

        return rawValue
            .split(separator: ",")
            .map { value in
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
    }

    static var mapboxAccessToken: String {
        let rawToken = (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawToken.isEmpty,
              rawToken != "YOUR_MAPBOX_PUBLIC_TOKEN",
              rawToken != "REPLACE_WITH_YOUR_MAPBOX_PUBLIC_TOKEN",
              !rawToken.hasPrefix("$(") else {
            #if DEBUG
            assertionFailure("Missing or invalid Mapbox access token. Set MAPBOX_ACCESS_TOKEN in Config.xcconfig.")
            #endif
            return ""
        }
        return rawToken
    }

    static var googleMapsAPIKey: String {
        let rawKey = (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawKey.isEmpty,
              rawKey != "YOUR_GOOGLE_MAPS_API_KEY",
              !rawKey.hasPrefix("$(") else {
            return ""
        }
        return rawKey
    }

    static var productionAppURL: URL {
        urlValue(for: "FLYR_PRO_API_URL") ?? URL(string: "https://flyrpro.app")!
    }

    static var dialerEnabledWorkspaceIDs: [UUID] {
        uuidListValue(for: dialerEnabledWorkspaceIDsKey)
    }

    static var dialerEnabledEmails: Set<String> {
        Set(normalizedStringListValue(for: dialerEnabledEmailsKey))
    }

    static func isDialerEnabled(workspaceID: UUID?, userEmail: String?) -> Bool {
        let normalizedEmail = userEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalizedEmail,
           dialerEnabledEmails.contains(normalizedEmail) {
            return true
        }

        guard let workspaceID else {
            return false
        }

        return dialerEnabledWorkspaceIDs.contains(workspaceID)
    }

    static func isDialerEnabledForWorkspace(_ workspaceID: UUID?) -> Bool {
        isDialerEnabled(workspaceID: workspaceID, userEmail: nil)
    }

    static var legacyPasswordRecoveryProductionURL: URL {
        URL(string: "https://flyrpro.app/auth/reset-password")!
    }

    static var passwordRecoveryProductionURL: URL {
        if let configured = urlValue(for: "FLYR_PASSWORD_RECOVERY_PRODUCTION_URL") {
            return configured
        }
        return URL(string: "https://www.flyrpro.app/password/reset")!
    }

    static var passwordRecoveryLocalCallbackURL: URL {
        urlValue(for: "FLYR_PASSWORD_RECOVERY_DEV_CALLBACK_URL")
            ?? URL(string: "flyr://auth/reset-password")!
    }

    static var passwordRecoveryRedirectURL: URL {
        if let configured = urlValue(for: "FLYR_PASSWORD_RECOVERY_REDIRECT_URL") {
            return configured
        }
        return passwordRecoveryProductionURL
    }

    static func matchesPasswordRecoveryURL(_ url: URL) -> Bool {
        if isPasswordRecoveryRootFallback(url) {
            return true
        }

        return passwordRecoveryAcceptedURLs.contains { expected in
            matches(url, expected: expected)
        }
    }

    static var passwordRecoveryAcceptedURLs: [URL] {
        var urls: [URL] = [
            passwordRecoveryProductionURL,
            legacyPasswordRecoveryProductionURL,
            passwordRecoveryLocalCallbackURL
        ]

        let productionVariants = [passwordRecoveryProductionURL, legacyPasswordRecoveryProductionURL]
            .flatMap(passwordRecoveryURLVariants(for:))
        urls.append(contentsOf: productionVariants)

        var seen = Set<String>()
        return urls.filter { url in
            let key = [
                normalizedComponents(for: url).scheme,
                normalizedComponents(for: url).host,
                normalizedComponents(for: url).path
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    private static func matches(_ candidate: URL, expected: URL) -> Bool {
        let candidateComponents = normalizedComponents(for: candidate)
        let expectedComponents = normalizedComponents(for: expected)
        return candidateComponents.scheme == expectedComponents.scheme
            && candidateComponents.host == expectedComponents.host
            && candidateComponents.path == expectedComponents.path
    }

    private static func normalizedComponents(for url: URL) -> (scheme: String, host: String, path: String) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme?.lowercased() ?? url.scheme?.lowercased() ?? ""
        let host = components?.host?.lowercased() ?? url.host?.lowercased() ?? ""
        let path = normalizedPath(components?.path ?? url.path)
        return (scheme, host, path)
    }

    private static func passwordRecoveryURLVariants(for url: URL) -> [URL] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            return [url]
        }

        let hostVariants: [String]
        switch host {
        case "flyr.software":
            hostVariants = ["flyr.software", "www.flyr.software"]
        case "www.flyr.software":
            hostVariants = ["www.flyr.software", "flyr.software"]
        case "flyrpro.app":
            hostVariants = ["flyrpro.app", "www.flyrpro.app"]
        case "www.flyrpro.app":
            hostVariants = ["www.flyrpro.app", "flyrpro.app"]
        default:
            hostVariants = [host]
        }

        return hostVariants.compactMap { variant in
            var variantComponents = components
            variantComponents.host = variant
            return variantComponents.url
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return "/" }
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        return trimmed
    }

    private static func isPasswordRecoveryRootFallback(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              ["flyrpro.app", "www.flyrpro.app", "flyr.software", "www.flyr.software"].contains(host),
              normalizedPath(components.path) == "/" else {
            return false
        }

        let queryItems = components.queryItems ?? []
        let queryMap = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name.lowercased(), $0.value ?? "") })

        if queryMap["type"]?.lowercased() == "recovery" {
            return true
        }

        let fragment = components.fragment ?? ""
        let fragmentPairs = fragment
            .split(separator: "&")
            .map { $0.split(separator: "=", maxSplits: 1) }
        let fragmentNames: Set<String> = Set(fragmentPairs.compactMap { pair -> String? in
            guard let raw = pair.first else { return nil }
            return String(raw).removingPercentEncoding?.lowercased() ?? String(raw).lowercased()
        })

        let signalNames = Set(queryMap.keys).union(fragmentNames)
        let recoveryMarkers = ["code", "token", "token_hash", "access_token", "refresh_token"]
        return recoveryMarkers.contains(where: signalNames.contains)
    }
}
