import Foundation
import Supabase

/// Manages syncing leads to connected CRM integrations
actor LeadSyncManager {
    static let shared = LeadSyncManager()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    /// Sync a lead to all connected CRM integrations
    /// - Parameters:
    ///   - lead: The lead to sync
    ///   - userId: The user ID who owns the lead
    /// - Returns: True if sync was initiated successfully (non-blocking)
    func syncLeadToCRM(lead: LeadModel, userId: UUID) async {
        // Validate lead has at least one contact field
        guard lead.isValidLead else {
            print("⚠️ [LeadSyncManager] Skipping sync - lead missing contact information")
            return
        }
        
        // Call Supabase Edge Function asynchronously (non-blocking)
        Task.detached(priority: .utility) {
            do {
                let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String
                let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
                let url = URL(string: "\(supabaseURLString)/functions/v1/crm_sync")!
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Get auth token
                let session = try await SupabaseManager.shared.client.auth.session
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
                
                // Encode lead to JSON
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                let leadDict: [String: Any] = [
                    "id": lead.id.uuidString,
                    "name": lead.name as Any,
                    "phone": lead.phone as Any,
                    "email": lead.email as Any,
                    "address": lead.address as Any,
                    "source": lead.source,
                    "campaign_id": lead.campaignId?.uuidString as Any,
                    "notes": lead.notes as Any,
                    "created_at": ISO8601DateFormatter().string(from: lead.createdAt)
                ]
                
                // Remove nil values
                let filteredDict = leadDict.compactMapValues { $0 }
                
                request.httpBody = try JSONSerialization.data(withJSONObject: filteredDict)
                
                // Make request
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [LeadSyncManager] Invalid response")
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("✅ [LeadSyncManager] Lead synced successfully: \(responseString)")
                    }
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("⚠️ [LeadSyncManager] Sync failed: \(httpResponse.statusCode) - \(errorMessage)")
                }
            } catch {
                // Log error but don't break app flow
                print("⚠️ [LeadSyncManager] Error syncing lead: \(error.localizedDescription)")
            }
        }
    }
}


