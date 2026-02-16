import Foundation
import Supabase

/// Optional appointment/task data sent when pushing a lead to CRM (e.g. FUB).
struct LeadSyncAppointment {
    let date: Date
    let title: String?
    let notes: String?
}

struct LeadSyncTask {
    let title: String
    let dueDate: Date
}

/// Manages syncing leads to connected CRM integrations
actor LeadSyncManager {
    static let shared = LeadSyncManager()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    /// Sync a lead to all connected CRM integrations.
    /// Pushes to Follow Up Boss via FLYR API (crm_connection_secrets) when connected, then to other CRMs via Edge Function (user_integrations).
    /// - Parameters:
    ///   - lead: The lead to sync
    ///   - userId: The user ID who owns the lead
    ///   - appointment: Optional appointment to create in CRM (e.g. FUB) after syncing the person
    ///   - task: Optional task to create in CRM (e.g. FUB) after syncing the person
    func syncLeadToCRM(lead: LeadModel, userId: UUID, appointment: LeadSyncAppointment? = nil, task: LeadSyncTask? = nil) async {
        guard lead.isValidLead else {
            print("⚠️ [LeadSyncManager] Skipping sync - lead missing contact information")
            return
        }

        // Sync to all connected CRMs (FUB, KVCore, Zapier, etc.) via Edge Function
        // FUB connection is managed via web at Settings → Integrations
        // The Edge Function reads from user_integrations table and syncs to all connected CRMs
        Task.detached(priority: .utility) {
            do {
                let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String
                let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
                let url = URL(string: "\(supabaseURLString)/functions/v1/crm_sync")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let session = try await SupabaseManager.shared.client.auth.session
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
                var leadDict: [String: Any] = [
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
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let appointment = appointment {
                    var appointmentDict: [String: Any] = ["date": formatter.string(from: appointment.date)]
                    if let t = appointment.title, !t.isEmpty { appointmentDict["title"] = t }
                    if let n = appointment.notes, !n.isEmpty { appointmentDict["notes"] = n }
                    leadDict["appointment"] = appointmentDict
                }
                if let task = task {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    dateFormatter.timeZone = TimeZone(identifier: "UTC")
                    leadDict["task"] = [
                        "title": task.title,
                        "due_date": dateFormatter.string(from: task.dueDate)
                    ]
                }
                let payload: [String: Any] = [
                    "lead": leadDict.compactMapValues { $0 },
                    "user_id": userId.uuidString
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                // Debug: print what's being sent
                if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                    print("📤 [LeadSyncManager] crm_sync request body: \(bodyString)")
                }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return }
                if httpResponse.statusCode == 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? ""
                    print("✅ [LeadSyncManager] Lead synced via Edge Function: \(responseString)")
                    
                    // Parse response to check results
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let synced = json["synced"] as? [String] ?? []
                        let failed = json["failed"] as? [[String: Any]] ?? []
                        
                        print("🔍 [LeadSyncManager] Parsed synced: \(synced.count), failed: \(failed.count)")
                        
                        if synced.isEmpty && failed.isEmpty {
                            print("ℹ️ [LeadSyncManager] No CRM integrations connected. Connect at: https://flyrpro.app/settings/integrations")
                        } else if !failed.isEmpty {
                            for fail in failed {
                                print("🔍 [LeadSyncManager] Processing fail: \(fail)")
                                if let provider = fail["provider"] as? String,
                                   let error = fail["error"] as? String {
                                    print("⚠️ [LeadSyncManager] \(provider) sync failed: \(error)")
                                    if error.contains("expired") || error.contains("401") {
                                        print("🔑 [LeadSyncManager] Token expired. Reconnect \(provider) at: https://flyrpro.app/settings/integrations")
                                    }
                                } else {
                                    print("⚠️ [LeadSyncManager] Could not parse fail entry: \(fail)")
                                }
                            }
                        }
                    } else {
                        print("⚠️ [LeadSyncManager] Failed to parse JSON response")
                    }
                } else {
                    print("⚠️ [LeadSyncManager] Edge Function sync failed: \(httpResponse.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                }
            } catch {
                print("⚠️ [LeadSyncManager] Error syncing lead: \(error.localizedDescription)")
            }
        }
    }
}


