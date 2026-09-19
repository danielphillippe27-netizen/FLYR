import Foundation
import Supabase

/// Lightweight online contact access for the Sales app. Field-app offline repositories are intentionally excluded.
actor SalespersonContactsService {
    static let shared = SalespersonContactsService()

    private var client: SupabaseClient { SupabaseManager.shared.client }

    func fetchContacts(userID: UUID, workspaceId: UUID? = nil) async throws -> [Contact] {
        var query = client
            .from("contacts")
            .select()
            .eq("user_id", value: userID)

        if let workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        }

        return try await query
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func updateContact(
        _ contact: Contact,
        userID: UUID? = nil,
        workspaceId: UUID? = nil,
        addressId: UUID? = nil,
        syncToCRM: Bool = true
    ) async throws -> Contact {
        let payload: [String: AnyCodable] = [
            "id": AnyCodable(contact.id),
            "user_id": AnyCodable(userID as Any),
            "workspace_id": AnyCodable(workspaceId as Any),
            "full_name": AnyCodable(contact.fullName),
            "phone": AnyCodable(contact.phone as Any),
            "email": AnyCodable(contact.email as Any),
            "company": AnyCodable(contact.company as Any),
            "address": AnyCodable(contact.address),
            "campaign_id": AnyCodable(contact.campaignId as Any),
            "farm_id": AnyCodable(contact.farmId as Any),
            "address_id": AnyCodable((addressId ?? contact.addressId) as Any),
            "lead_kind": AnyCodable(contact.leadKind as Any),
            "tags": AnyCodable(contact.tags as Any),
            "status": AnyCodable(contact.status.rawValue),
            "last_contacted": AnyCodable(contact.lastContacted as Any),
            "notes": AnyCodable(contact.notes as Any),
            "reminder_date": AnyCodable(contact.reminderDate as Any),
            "follow_up_at": AnyCodable(contact.followUpAt as Any),
            "appointment_at": AnyCodable(contact.appointmentAt as Any),
            "updated_at": AnyCodable(contact.updatedAt),
        ]

        let rows: [Contact] = try await client
            .from("contacts")
            .upsert(payload, onConflict: "id")
            .select()
            .execute()
            .value

        return rows.first ?? contact
    }
}
