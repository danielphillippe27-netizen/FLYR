import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    
    // Load your values from Info.plist or Config.xcconfig
    private let supabaseURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String)!
    private let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
    
    let client: SupabaseClient
    
    private init() {
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }
}
