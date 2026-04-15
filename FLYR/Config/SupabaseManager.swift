import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        let supabaseURLString = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let supabaseKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let supabaseURL: URL
        if let parsedURL = URL(string: supabaseURLString), !supabaseURLString.isEmpty, !supabaseKey.isEmpty {
            supabaseURL = parsedURL
        } else {
            #if DEBUG
            assertionFailure("Missing or invalid Supabase configuration in Info.plist.")
            #endif
            supabaseURL = URL(string: "https://invalid.local")!
        }

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
