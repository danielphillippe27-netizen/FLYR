import Foundation
import Supabase

/// API for logging building visits/touches and updating campaign address visited status
final class VisitsAPI {
    static let shared = VisitsAPI()
    private init() {}
    
    private let client = SupabaseManager.shared.client
    
    /// Log a building touch/visit event
    /// - Parameters:
    ///   - addressId: UUID of the campaign address (from campaign_addresses.id)
    ///   - campaignId: UUID of the campaign
    ///   - buildingId: Mapbox building ID (optional, may be nil for some buildings)
    ///   - sessionId: Current session ID (optional, nil if not tracking active session)
    func logBuildingTouch(
        addressId: UUID,
        campaignId: UUID,
        buildingId: String?,
        sessionId: UUID?
    ) {
        // Fire and forget - non-blocking async call
        Task {
            do {
                print("🏗️ [VisitsAPI] Logging building touch: addressId=\(addressId), campaignId=\(campaignId), buildingId=\(buildingId ?? "nil"), sessionId=\(sessionId?.uuidString ?? "nil")")
                
                // TODO: Insert into building_touches table when backend is ready
                // For now, just log the event
                // Example future implementation:
                // var touchData: [String: AnyCodable] = [
                //     "address_id": AnyCodable(addressId.uuidString),
                //     "campaign_id": AnyCodable(campaignId.uuidString),
                //     "user_id": AnyCodable(userId.uuidString),
                //     "touched_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
                // ]
                // if let buildingId = buildingId {
                //     touchData["building_id"] = AnyCodable(buildingId)
                // }
                // if let sessionId = sessionId {
                //     touchData["session_id"] = AnyCodable(sessionId.uuidString)
                // }
                // _ = try await client.from("building_touches").insert(touchData).execute()
                
                print("✅ [VisitsAPI] Building touch logged (future: will insert into building_touches table)")
            } catch {
                // Log error but don't block user interaction
                print("⚠️ [VisitsAPI] Error logging building touch: \(error.localizedDescription)")
            }
        }
    }
    
    /// Mark a campaign address as visited
    /// - Parameter addressId: UUID of the campaign address (from campaign_addresses.id)
    func markAddressVisited(addressId: UUID) {
        // Fire and forget - non-blocking async update
        Task {
            do {
                print("📍 [VisitsAPI] Marking address visited: addressId=\(addressId)")
                
                // Update campaign_addresses.visited = true
                let updateData: [String: AnyCodable] = [
                    "visited": AnyCodable(true)
                ]
                
                _ = try await client
                    .from("campaign_addresses")
                    .update(updateData)
                    .eq("id", value: addressId.uuidString)
                    .execute()
                
                print("✅ [VisitsAPI] Address marked as visited: \(addressId)")
            } catch {
                // Log error but don't block user interaction
                print("⚠️ [VisitsAPI] Error marking address as visited: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch all address statuses for a campaign
    /// - Parameter campaignId: UUID of the campaign
    /// - Returns: Dictionary mapping address_id to AddressStatusRow
    func fetchStatuses(campaignId: UUID) async throws -> [UUID: AddressStatusRow] {
        print("📊 [VisitsAPI] Fetching statuses for campaign: \(campaignId)")
        
        let response = try await client
            .from("address_statuses")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        
        #if DEBUG
        let raw = String(data: response.data, encoding: .utf8) ?? ""
        let preview = String(raw.prefix(2048))
        print("[VisitsAPI DEBUG] address_statuses raw JSON (first 2KB): \(preview)\(raw.count > 2048 ? "…" : "")")
        #endif
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows: [AddressStatusRow] = try decoder.decode([AddressStatusRow].self, from: response.data)
        
        var statuses: [UUID: AddressStatusRow] = [:]
        for statusRow in rows {
            statuses[statusRow.addressId] = statusRow
        }
        
        print("✅ [VisitsAPI] Fetched \(statuses.count) statuses for campaign \(campaignId)")
        return statuses
    }
    
    /// Update or create address status
    /// - Parameters:
    ///   - addressId: UUID of the campaign address
    ///   - campaignId: UUID of the campaign
    ///   - status: New status value
    ///   - notes: Optional notes
    func updateStatus(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil
    ) async throws {
        print("📝 [VisitsAPI] Updating status: addressId=\(addressId), campaignId=\(campaignId), status=\(status.rawValue)")
        
        let now = Date()
        
        // First, try to fetch existing status to get current visit_count
        var existingStatus: AddressStatusRow? = nil
        do {
            let res: PostgrestResponse<[AddressStatusRow]> = try await client
                .from("address_statuses")
                .select()
                .eq("address_id", value: addressId.uuidString)
                .eq("campaign_id", value: campaignId.uuidString)
                .limit(1)
                .execute()
            existingStatus = res.value.first
        } catch {
            // If fetch fails, we'll create new status with visit_count = 1
            print("ℹ️ [VisitsAPI] No existing status found, will create new one")
        }
        
        let newVisitCount = (existingStatus?.visitCount ?? 0) + 1
        
        let updateData: [String: AnyCodable] = [
            "address_id": AnyCodable(addressId.uuidString),
            "campaign_id": AnyCodable(campaignId.uuidString),
            "status": AnyCodable(status.rawValue),
            "last_visited_at": AnyCodable(ISO8601DateFormatter().string(from: now)),
            "visit_count": AnyCodable(newVisitCount),
            "notes": AnyCodable(notes ?? "")
        ]
        
        // Use upsert to create or update
        _ = try await client
            .from("address_statuses")
            .upsert(updateData, onConflict: "address_id,campaign_id")
            .execute()
        
        print("✅ [VisitsAPI] Status updated: \(addressId) -> \(status.rawValue) (visit_count: \(newVisitCount))")
    }
}

