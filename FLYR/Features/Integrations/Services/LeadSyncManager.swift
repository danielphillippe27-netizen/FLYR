import Foundation
import Supabase

/// CRM sync lifecycle for field leads persisted via `FieldLeadsService` (`sync_status` on contacts).
enum FieldLeadCRMSyncLifecycle: Sendable {
    case started(leadId: UUID)
    case finished(leadId: UUID, status: FieldLeadSyncStatus, detail: String?)
}

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
    ///   - trackFieldLeadCRMStatus: When true, updates `contacts` / `field_leads` `sync_status` for this lead id.
    func syncLeadToCRM(
        lead: LeadModel,
        userId: UUID,
        appointment: LeadSyncAppointment? = nil,
        task: LeadSyncTask? = nil,
        trackFieldLeadCRMStatus: Bool = false
    ) async {
        guard lead.isValidLead else {
            print("⚠️ [LeadSyncManager] Skipping sync - lead missing contact information")
            return
        }
        let dedupeKey = makeDedupeKey(for: lead, userId: userId, appointment: appointment, task: task)
        guard shouldProceed(with: dedupeKey) else {
            print("ℹ️ [LeadSyncManager] Skipping duplicate sync for key: \(dedupeKey)")
            return
        }

        let enriched = CRMLeadEnrichment.enrichedForSecureProviders(lead)
        if trackFieldLeadCRMStatus {
            await FieldLeadsService.shared.applyCRMLifecycle(.started(leadId: lead.id), userId: userId)
        }

        let leadId = lead.id
        // Push to secure backend providers first, then sync the rest via Edge Function.
        Task.detached(priority: .utility) {
            var anySecureSuccess = false
            var explicitFailure = false
            var edgeSynced = false
            var edgeHttpNotOk = false

            defer {
                if trackFieldLeadCRMStatus {
                    let status: FieldLeadSyncStatus
                    if anySecureSuccess || edgeSynced {
                        status = .synced
                    } else if explicitFailure || edgeHttpNotOk {
                        status = .failed
                    } else {
                        status = .pending
                    }
                    Task {
                        await FieldLeadsService.shared.applyCRMLifecycle(
                            .finished(leadId: leadId, status: status, detail: nil),
                            userId: userId
                        )
                    }
                }
            }

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
                        enriched,
                        appointment: appointment,
                        task: task
                    )
                    excludeProvider("fub")
                    anySecureSuccess = true
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
                        explicitFailure = true
                        excludeProvider("fub")
                        print("⚠️ [LeadSyncManager] Secure FUB auth failed: \(msg)")
                    case .tokenExpired(let msg):
                        explicitFailure = true
                        excludeProvider("fub")
                        print("⚠️ [LeadSyncManager] Secure FUB token expired: \(msg)")
                    default:
                        explicitFailure = true
                        excludeProvider("fub")
                        print("⚠️ [LeadSyncManager] Secure FUB push failed: \(fubError.localizedDescription)")
                    }
                } catch {
                    explicitFailure = true
                    excludeProvider("fub")
                    print("⚠️ [LeadSyncManager] Secure FUB push error: \(error.localizedDescription)")
                }

                // BoldTrail secure push (workspace-scoped connection on FLYR-PRO backend routes).
                do {
                    _ = try await BoldTrailPushLeadAPI.shared.pushLead(enriched)
                    excludeProvider("boldtrail")
                    anySecureSuccess = true
                    print("✅ [LeadSyncManager] Lead pushed to BoldTrail via secure backend route")
                } catch let boldTrailError as BoldTrailPushLeadError {
                    switch boldTrailError {
                    case .notConnected:
                        print("ℹ️ [LeadSyncManager] BoldTrail not connected via secure flow; skipping secure BoldTrail push")
                    case .invalidLead(let msg):
                        excludeProvider("boldtrail")
                        print("ℹ️ [LeadSyncManager] Skipping secure BoldTrail push: \(msg)")
                    case .unauthorized(let msg):
                        explicitFailure = true
                        excludeProvider("boldtrail")
                        print("⚠️ [LeadSyncManager] Secure BoldTrail auth failed: \(msg)")
                    default:
                        explicitFailure = true
                        excludeProvider("boldtrail")
                        print("⚠️ [LeadSyncManager] Secure BoldTrail push failed: \(boldTrailError.localizedDescription)")
                    }
                } catch {
                    explicitFailure = true
                    excludeProvider("boldtrail")
                    print("⚠️ [LeadSyncManager] Secure BoldTrail push error: \(error.localizedDescription)")
                }

                // HubSpot secure push (FLYR-PRO backend stores tokens server-side).
                do {
                    let hubRes = try await HubSpotPushLeadAPI.shared.pushLead(enriched, appointment: appointment, task: task)
                    excludeProvider("hubspot")
                    anySecureSuccess = true
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
                        explicitFailure = true
                        excludeProvider("hubspot")
                        print("⚠️ [LeadSyncManager] Secure HubSpot auth failed: \(msg)")
                    default:
                        explicitFailure = true
                        excludeProvider("hubspot")
                        print("⚠️ [LeadSyncManager] Secure HubSpot push failed: \(hubSpotError.localizedDescription)")
                    }
                } catch {
                    explicitFailure = true
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
                    "id": enriched.id.uuidString,
                    "name": enriched.name as Any,
                    "phone": enriched.phone as Any,
                    "email": enriched.email as Any,
                    "address": enriched.address as Any,
                    "source": enriched.source,
                    "campaign_id": enriched.campaignId?.uuidString as Any,
                    "notes": enriched.notes as Any,
                    "created_at": ISO8601DateFormatter().string(from: enriched.createdAt)
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
                guard let httpResponse = response as? HTTPURLResponse else {
                    edgeHttpNotOk = true
                    return
                }
                if httpResponse.statusCode == 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? ""
                    print("✅ [LeadSyncManager] Lead synced via Edge Function: \(responseString)")

                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let synced = json["synced"] as? [Any] ?? []
                        let failed = json["failed"] as? [[String: Any]] ?? []

                        if !synced.isEmpty {
                            edgeSynced = true
                        }

                        print("🔍 [LeadSyncManager] Parsed synced: \(synced.count), failed: \(failed.count)")

                        if synced.isEmpty && failed.isEmpty {
                            print("ℹ️ [LeadSyncManager] No CRM integrations connected. Connect at: https://flyrpro.app/settings/integrations")
                        } else if !failed.isEmpty, synced.isEmpty {
                            explicitFailure = true
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
                    edgeHttpNotOk = true
                    print("⚠️ [LeadSyncManager] Edge Function sync failed: \(httpResponse.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                }
            } catch {
                explicitFailure = true
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
