import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient
    let supabaseURLString: String
    let anonKey: String
    let isLocalE2E: Bool
    let localE2EWorkspaceID: UUID?

    private init() {
        let bundledURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundledKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let requestedURL = environment["WOLFGRID_E2E_SUPABASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedKey = environment["WOLFGRID_E2E_SUPABASE_ANON_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isExplicitE2E = environment["WOLFGRID_E2E"] == "1"
        let isLoopbackTarget = requestedURL.flatMap(URL.init(string:)).map {
            ["127.0.0.1", "localhost", "::1"].contains($0.host?.lowercased() ?? "")
        } == true
        let urlString = isExplicitE2E && isLoopbackTarget ? (requestedURL ?? bundledURL) : bundledURL
        let key = isExplicitE2E && isLoopbackTarget ? (requestedKey ?? bundledKey) : bundledKey
        let isLocalE2E = isExplicitE2E && isLoopbackTarget
        let localE2EWorkspaceID = isLocalE2E
            ? environment["WOLFGRID_E2E_WORKSPACE_ID"].flatMap { UUID(uuidString: $0) }
            : nil
        #else
        let urlString = bundledURL
        let key = bundledKey
        let isLocalE2E = false
        let localE2EWorkspaceID: UUID? = nil
        #endif

        self.supabaseURLString = urlString
        self.anonKey = key
        self.isLocalE2E = isLocalE2E
        self.localE2EWorkspaceID = localE2EWorkspaceID

        let supabaseURL: URL
        if let parsedURL = URL(string: supabaseURLString), !supabaseURLString.isEmpty, !anonKey.isEmpty {
            supabaseURL = parsedURL
        } else {
            #if DEBUG
            assertionFailure("Missing or invalid Supabase configuration in Info.plist.")
            #endif
            supabaseURL = URL(string: "https://invalid.local")!
        }

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: anonKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
