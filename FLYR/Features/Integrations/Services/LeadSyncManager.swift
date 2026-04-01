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
    private let duplicateWindow: TimeInterval = 8
    private var recentSyncs: [String: Date] = [:]
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    /// Sync a lead to connected CRM integrations.
    /// Follow Up Boss remains the native/special-case path via secure backend routes.
    /// All other CRM providers flow through the shared provider sync pipeline.
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
        let dedupeKey = makeDedupeKey(for: lead, userId: userId, appointment: appointment, task: task)
        guard shouldProceed(with: dedupeKey) else {
            print("ℹ️ [LeadSyncManager] Skipping duplicate sync for key: \(dedupeKey)")
            return
        }

        // Push to secure backend providers first, then sync the rest via Edge Function.
        Task.detached(priority: .utility) {
            do {
                var excludedProviders: [String] = []
                func excludeProvider(_ provider: String) {
                    if !excludedProviders.contains(provider) {
                        excludedProviders.append(provider)
                    }
                }

                // FUB secure push (crm_connection_secrets via FLYR backend routes).
                do {
                    let fubResponse = try await FUBPushLeadAPI.shared.pushLead(
                        lead,
                        appointment: appointment,
                        task: task
                    )
                    excludeProvider("fub")
                    print("✅ [LeadSyncManager] Lead pushed to FUB via secure backend route")
                    if let followUpErrors = fubResponse.followUpErrors, !followUpErrors.isEmpty {
                        let summary = followUpErrors.joined(separator: " | ")
                        print("⚠️ [LeadSyncManager] FUB follow-up issues: \(summary)")
                        for err in followUpErrors {
                            print("⚠️ [LeadSyncManager] FUB follow-up detail: \(err)")
                        }
                    }
                    if appointment != nil, fubResponse.fubAppointmentId == nil {
                        if fubResponse.appointmentCreated != true {
                            print("⚠️ [LeadSyncManager] Appointment payload was sent but FUB did not confirm creation")
                        }
                    }
                    if task != nil, fubResponse.fubTaskId == nil {
                        if fubResponse.taskCreated != true {
                            print("⚠️ [LeadSyncManager] Task payload was sent but FUB did not confirm creation")
                        }
                    }
                    if (lead.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false),
                       fubResponse.noteCreated != true {
                        print("⚠️ [LeadSyncManager] Note payload was sent but FUB did not confirm creation")
                    }
                } catch let fubError as FUBPushLeadError {
                    switch fubError {
                    case .notConnected:
                        print("ℹ️ [LeadSyncManager] FUB not connected via secure flow; skipping secure FUB push")
                    case .invalidLead(let msg):
                        excludeProvider("fub")
                        print("ℹ️ [LeadSyncManager] Skipping secure FUB push: \(msg)")
                    case .unauthorized(let msg):
                        excludeProvider("fub")
                        print("⚠️ [LeadSyncManager] Secure FUB auth failed: \(msg)")
                    case .tokenExpired(let msg):
                        excludeProvider("fub")
                        print("⚠️ [LeadSyncManager] Secure FUB token expired: \(msg)")
                    default:
                        excludeProvider("fub")
                        print("⚠️ [LeadSyncManager] Secure FUB push failed: \(fubError.localizedDescription)")
                    }
                } catch {
                    excludeProvider("fub")
                    print("⚠️ [LeadSyncManager] Secure FUB push error: \(error.localizedDescription)")
                }

                // BoldTrail secure push (workspace-scoped connection on FLYR-PRO backend routes).
                do {
                    _ = try await BoldTrailPushLeadAPI.shared.pushLead(lead)
                    excludeProvider("boldtrail")
                    print("✅ [LeadSyncManager] Lead pushed to BoldTrail via secure backend route")
                } catch let boldTrailError as BoldTrailPushLeadError {
                    switch boldTrailError {
                    case .notConnected:
                        print("ℹ️ [LeadSyncManager] BoldTrail not connected via secure flow; skipping secure BoldTrail push")
                    case .invalidLead(let msg):
                        excludeProvider("boldtrail")
                        print("ℹ️ [LeadSyncManager] Skipping secure BoldTrail push: \(msg)")
                    case .unauthorized(let msg):
                        excludeProvider("boldtrail")
                        print("⚠️ [LeadSyncManager] Secure BoldTrail auth failed: \(msg)")
                    default:
                        excludeProvider("boldtrail")
                        print("⚠️ [LeadSyncManager] Secure BoldTrail push failed: \(boldTrailError.localizedDescription)")
                    }
                } catch {
                    excludeProvider("boldtrail")
                    print("⚠️ [LeadSyncManager] Secure BoldTrail push error: \(error.localizedDescription)")
                }

                // HubSpot secure push (FLYR-PRO backend stores tokens server-side).
                do {
                    let hubRes = try await HubSpotPushLeadAPI.shared.pushLead(lead, appointment: appointment, task: task)
                    excludeProvider("hubspot")
                    print("✅ [LeadSyncManager] Lead pushed to HubSpot via secure backend route")
                    if let errs = hubRes.partialErrors, !errs.isEmpty {
                        for err in errs {
                            print("⚠️ [LeadSyncManager] HubSpot follow-up: \(err)")
                        }
                    }
                } catch let hubSpotError as HubSpotPushLeadError {
                    switch hubSpotError {
                    case .notConnected:
                        print("ℹ️ [LeadSyncManager] HubSpot not connected; skipping secure HubSpot push")
                    case .invalidLead(let msg):
                        excludeProvider("hubspot")
                        print("ℹ️ [LeadSyncManager] Skipping secure HubSpot push: \(msg)")
                    case .unauthorized(let msg):
                        excludeProvider("hubspot")
                        print("⚠️ [LeadSyncManager] Secure HubSpot auth failed: \(msg)")
                    default:
                        excludeProvider("hubspot")
                        print("⚠️ [LeadSyncManager] Secure HubSpot push failed: \(hubSpotError.localizedDescription)")
                    }
                } catch {
                    excludeProvider("hubspot")
                    print("⚠️ [LeadSyncManager] Secure HubSpot push error: \(error.localizedDescription)")
                }

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
                var payloadWithExclusions = payload
                if !excludedProviders.isEmpty {
                    payloadWithExclusions["exclude_providers"] = excludedProviders
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: payloadWithExclusions)
                
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

    private func shouldProceed(with key: String) -> Bool {
        let now = Date()
        recentSyncs = recentSyncs.filter { now.timeIntervalSince($0.value) < duplicateWindow }
        if let last = recentSyncs[key], now.timeIntervalSince(last) < duplicateWindow {
            return false
        }
        recentSyncs[key] = now
        return true
    }

    private func makeDedupeKey(
        for lead: LeadModel,
        userId: UUID,
        appointment: LeadSyncAppointment?,
        task: LeadSyncTask?
    ) -> String {
        let normalized = {
            (value: String?) in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }
        let appointmentDate = appointment.map { ISO8601DateFormatter().string(from: $0.date) } ?? ""
        let taskDate = task.map { ISO8601DateFormatter().string(from: $0.dueDate) } ?? ""
        return [
            userId.uuidString.lowercased(),
            lead.id.uuidString.lowercased(),
            normalized(lead.email),
            normalized(lead.phone),
            normalized(lead.address),
            normalized(lead.notes),
            normalized(appointment?.title),
            normalized(appointment?.notes),
            appointmentDate,
            normalized(task?.title),
            taskDate
        ].joined(separator: "|")
    }
}
