import Foundation
import Supabase

actor StatsService {
    static let shared = StatsService()

    private struct StatsContactRow: Decodable {
        let id: UUID
        let status: String?
    }

    private struct StatsLegacyLeadRow: Decodable {
        let id: UUID
        let address: String?
    }

    private struct StatsAppointmentActivityRow: Decodable {
        let id: UUID
        let contactId: UUID
        let note: String?
        let timestamp: Date

        enum CodingKeys: String, CodingKey {
            case id
            case contactId = "contact_id"
            case note
            case timestamp
        }
    }
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch User Stats
    
    func fetchUserStats(userID: UUID) async throws -> UserStats? {
        let response: [UserStats] = try await client
            .from("user_stats")
            .select()
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value

        let base = response.first ?? UserStats(user_id: userID)
        return try await mergedWithLiveLeadAndAppointmentCounts(base, userID: userID)
    }
    
    // MARK: - Upsert User Stats
    
    func upsertUserStats(_ stats: UserStats) async throws {
        try await client
            .from("user_stats")
            .upsert(stats, onConflict: "user_id")
            .execute()
    }
    
    // MARK: - Update Specific Stat Field
    
    func updateStat(userID: UUID, field: String, value: Any) async throws {
        // Use AnyCodable for proper encoding
        let updateValue: AnyCodable = AnyCodable(value)
        
        try await client
            .from("user_stats")
            .update([field: updateValue])
            .eq("user_id", value: userID)
            .execute()
    }

    func refreshUserStatsFromSessions(userID: UUID) async throws {
        struct RefreshStatsParams: Encodable {
            let p_user_id: UUID
        }

        _ = try await client
            .rpc("refresh_user_stats_from_sessions", params: RefreshStatsParams(p_user_id: userID))
            .execute()
    }

    private func mergedWithLiveLeadAndAppointmentCounts(_ stats: UserStats, userID: UUID) async throws -> UserStats {
        async let liveLeadCount = fetchLiveLeadCount(userID: userID)
        async let liveAppointmentCount = fetchLiveAppointmentCount(userID: userID)

        let resolvedLeads = max(stats.leads_created, try await liveLeadCount)
        let resolvedAppointments = max(stats.appointments, try await liveAppointmentCount)
        let resolvedLeadRate = stats.conversations > 0
            ? Double(resolvedLeads) / Double(stats.conversations)
            : stats.conversation_lead_rate

        return UserStats(
            id: stats.id,
            user_id: stats.user_id,
            day_streak: stats.day_streak,
            best_streak: stats.best_streak,
            doors_knocked: stats.doors_knocked,
            flyers: stats.flyers,
            conversations: stats.conversations,
            leads_created: resolvedLeads,
            appointments: resolvedAppointments,
            qr_codes_scanned: stats.qr_codes_scanned,
            distance_walked: stats.distance_walked,
            time_tracked: stats.time_tracked,
            conversation_per_door: stats.conversation_per_door,
            conversation_lead_rate: resolvedLeadRate,
            qr_code_scan_rate: stats.qr_code_scan_rate,
            qr_code_lead_rate: stats.qr_code_lead_rate,
            streak_days: stats.streak_days,
            xp: stats.xp,
            updated_at: stats.updated_at,
            created_at: stats.created_at
        )
    }

    private func fetchLiveLeadCount(userID: UUID) async throws -> Int {
        // Filter to field-captured leads only. Salesperson-imported (scraped) contacts are
        // stored with lead_kind = 'scraped' and must not appear in doorknocker stats.
        let cachedContacts = await ContactRepository.shared.fetchContacts(userId: userID)
            .filter { $0.leadKind == nil || $0.leadKind == "field" }
        var leadKeys = Set(cachedContacts.map { leadKey(id: $0.id, address: $0.address) })

        do {
            let remoteContacts: [StatsContactRow] = try await client
                .from("contacts")
                .select("id,status")
                .eq("user_id", value: userID)
                .eq("lead_kind", value: "field")
                .execute()
                .value
            leadKeys.formUnion(remoteContacts.map { leadKey(id: $0.id, address: nil) })
        } catch {
            if leadKeys.isEmpty { throw error }
        }

        do {
            let legacyRows: [StatsLegacyLeadRow] = try await client
                .from("field_leads")
                .select("id,address")
                .eq("user_id", value: userID)
                .execute()
                .value
            leadKeys.formUnion(legacyRows.map { leadKey(id: $0.id, address: $0.address) })
        } catch {
            if leadKeys.isEmpty { throw error }
        }

        return leadKeys.count
    }

    private func fetchLiveAppointmentCount(userID: UUID) async throws -> Int {
        let cachedContacts = await ContactRepository.shared.fetchContacts(userId: userID)
        let cachedContactIds = Set(cachedContacts.map(\.id))
        let cachedActivities = await ContactRepository.shared.fetchActivities(
            contactIds: Array(cachedContactIds),
            type: .meeting,
            limit: 5_000
        )
        var appointmentKeys = Set(cachedActivities.map {
            appointmentKey(contactId: $0.contactId, timestamp: $0.timestamp, note: $0.note)
        })

        do {
            let response = try await client
                .from("contact_activities")
                .select("id,contact_id,note,timestamp,contacts!inner(id,user_id)")
                .eq("type", value: ActivityType.meeting.rawValue)
                .eq("contacts.user_id", value: userID.uuidString)
                .execute()

            let remoteActivities = try JSONDecoder.supabaseDates.decode([StatsAppointmentActivityRow].self, from: response.data)
            appointmentKeys.formUnion(remoteActivities.map {
                appointmentKey(contactId: $0.contactId, timestamp: $0.timestamp, note: $0.note)
            })
        } catch {
            if appointmentKeys.isEmpty { throw error }
        }

        return appointmentKeys.count
    }

    private func leadKey(id: UUID, address: String?) -> String {
        let normalizedAddress = address?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
        return normalizedAddress.isEmpty ? id.uuidString.lowercased() : normalizedAddress
    }

    private func appointmentKey(contactId: UUID, timestamp: Date, note: String?) -> String {
        [
            contactId.uuidString.lowercased(),
            String(Int(timestamp.timeIntervalSince1970.rounded())),
            note?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        ].joined(separator: "|")
    }
}
