import Foundation
import Supabase

enum ActivityFeedFilter: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case appointments = "Appointments"
    case followUp = "Follow Up"

    var id: String { rawValue }
}

enum ActivityFeedKind {
    case session
    case appointment
    case followUp
}

struct ActivityFeedItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let timestamp: Date
    let kind: ActivityFeedKind
}

@MainActor
final class ActivityFeedService {
    static let shared = ActivityFeedService()

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private init() {}

    func fetchItems(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        filter: ActivityFeedFilter,
        limit: Int = 150
    ) async throws -> [ActivityFeedItem] {
        switch filter {
        case .activity:
            return try await fetchSessionItems(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
        case .appointments:
            let contacts = try await fetchContactRows(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
            return contacts
                .filter { isAppointmentStatus($0.status) }
                .map { row in
                    let status = prettyStatus(row.status)
                    let subtitle = "\(row.address) • \(status)"
                    return ActivityFeedItem(
                        id: "appointment-\(row.id.uuidString)",
                        title: displayName(for: row),
                        subtitle: subtitle,
                        timestamp: row.updatedAt ?? row.createdAt,
                        kind: .appointment
                    )
                }
                .sorted(by: { $0.timestamp > $1.timestamp })
        case .followUp:
            let contacts = try await fetchContactRows(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
            return contacts
                .filter { needsFollowUp($0) }
                .map { row in
                    let dueDate = row.reminderDate ?? row.updatedAt ?? row.createdAt
                    let subtitle: String
                    if row.reminderDate != nil {
                        subtitle = "\(row.address) • Follow up due"
                    } else {
                        subtitle = "\(row.address) • \(prettyStatus(row.status))"
                    }
                    return ActivityFeedItem(
                        id: "follow-up-\(row.id.uuidString)",
                        title: displayName(for: row),
                        subtitle: subtitle,
                        timestamp: dueDate,
                        kind: .followUp
                    )
                }
                .sorted(by: { $0.timestamp < $1.timestamp })
        }
    }

    private func fetchSessionItems(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        limit: Int
    ) async throws -> [ActivityFeedItem] {
        var query = client
            .from("sessions")
            .select("id,user_id,start_time,end_time,doors_hit,flyers_delivered,completed_count,conversations")

        if includeMembers, let workspaceId {
            query = query.eq("workspace_id", value: workspaceId.uuidString)
        } else {
            query = query.eq("user_id", value: userId.uuidString)
        }

        let response = try await query
            .order("start_time", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder.supabaseDates
        let rows = try decoder.decode([SessionFeedRow].self, from: response.data)

        return rows.map { row in
            let end = row.endTime ?? row.startTime
            let durationMinutes = max(1, Int(end.timeIntervalSince(row.startTime) / 60))
            let doors = row.doorsHit ?? row.flyersDelivered ?? row.completedCount ?? 0
            let conversations = max(0, row.conversations ?? 0)
            let memberPrefix = includeMembers && row.userId != userId ? "Team" : "Your"
            let title = row.endTime == nil ? "\(memberPrefix) session active" : "\(memberPrefix) session complete"
            var subtitle = "\(doors) homes • \(durationMinutes) min"
            if conversations > 0 {
                subtitle += " • \(conversations) conv"
            }
            return ActivityFeedItem(
                id: "session-\(row.id.uuidString)",
                title: title,
                subtitle: subtitle,
                timestamp: row.startTime,
                kind: .session
            )
        }
    }

    private func fetchContactRows(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        limit: Int
    ) async throws -> [ContactFeedRow] {
        let decoder = JSONDecoder.supabaseDates
        do {
            var query = client
                .from("contacts")
                .select("id,user_id,full_name,address,status,reminder_date,updated_at,created_at")
            if includeMembers, let workspaceId {
                query = query.eq("workspace_id", value: workspaceId.uuidString)
            } else {
                query = query.eq("user_id", value: userId.uuidString)
            }
            let response = try await query
                .order("updated_at", ascending: false)
                .limit(limit)
                .execute()
            let contacts = try decoder.decode([ContactFeedRow].self, from: response.data)
            if !contacts.isEmpty {
                return contacts
            }
        } catch {
            // Fall through to legacy field_leads when contacts are empty/unavailable.
        }

        var legacyQuery = client
            .from("field_leads")
            .select("id,user_id,name,address,status,updated_at,created_at")
        if includeMembers, let workspaceId {
            legacyQuery = legacyQuery.eq("workspace_id", value: workspaceId.uuidString)
        } else {
            legacyQuery = legacyQuery.eq("user_id", value: userId.uuidString)
        }
        let legacyResponse = try await legacyQuery
            .order("updated_at", ascending: false)
            .limit(limit)
            .execute()
        let legacyRows = try decoder.decode([LegacyLeadRow].self, from: legacyResponse.data)
        return legacyRows.map {
            ContactFeedRow(
                id: $0.id,
                userId: $0.userId,
                fullName: $0.name,
                address: $0.address,
                status: $0.status,
                reminderDate: nil,
                updatedAt: $0.updatedAt,
                createdAt: $0.createdAt
            )
        }
    }

    private func displayName(for row: ContactFeedRow) -> String {
        let trimmed = row.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? row.address : trimmed
    }

    private func prettyStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "not_home": return "Not home"
        case "no_answer": return "No answer"
        case "qr_scanned": return "QR scanned"
        case "follow_up": return "Follow up"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func isAppointmentStatus(_ raw: String) -> Bool {
        let normalized = raw.lowercased()
        return normalized == "interested" || normalized == "hot" || normalized == "appointment"
    }

    private func needsFollowUp(_ row: ContactFeedRow) -> Bool {
        if row.reminderDate != nil {
            return true
        }
        let normalized = row.status.lowercased()
        return normalized == "follow_up" || normalized == "not_home" || normalized == "no_answer" || normalized == "warm"
    }
}

private struct SessionFeedRow: Decodable {
    let id: UUID
    let userId: UUID
    let startTime: Date
    let endTime: Date?
    let doorsHit: Int?
    let flyersDelivered: Int?
    let completedCount: Int?
    let conversations: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case doorsHit = "doors_hit"
        case flyersDelivered = "flyers_delivered"
        case completedCount = "completed_count"
        case conversations
    }
}

private struct ContactFeedRow: Decodable {
    let id: UUID
    let userId: UUID?
    let fullName: String?
    let address: String
    let status: String
    let reminderDate: Date?
    let updatedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case address
        case status
        case reminderDate = "reminder_date"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

private struct LegacyLeadRow: Decodable {
    let id: UUID
    let userId: UUID?
    let name: String?
    let address: String
    let status: String
    let updatedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case address
        case status
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}
