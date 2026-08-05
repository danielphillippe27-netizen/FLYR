import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient
    let supabaseURLString: String
    let anonKey: String

    private init() {
        let urlString = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.supabaseURLString = urlString
        self.anonKey = key

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
