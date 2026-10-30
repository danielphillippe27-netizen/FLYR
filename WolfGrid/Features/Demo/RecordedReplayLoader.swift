import Foundation
import CoreLocation
import Supabase

/// Loads only real samples and outcome events; missing history is never synthesized.
@MainActor
enum RecordedReplayLoader {
    enum LoadError: LocalizedError {
        case missingGPS
        case missingEvents
        case unsyncedEvents
        var errorDescription: String? {
            switch self {
            case .missingGPS: return "Timestamped GPS history is unavailable on this device for this session."
            case .missingEvents: return "Recorded visit outcomes are missing or incomplete for this session."
            case .unsyncedEvents: return "Some session outcomes have not synced yet. Connect and resolve any sync issues before creating a replay."
            }
        }
    }

    static func load(sessionID: UUID) async throws -> RecordedReplayTimeline {
        let stored = await SessionRepository.shared.getSessionPoints(sessionId: sessionID)
        let points = stored.filter(\.accepted).map { RecordedReplayPoint(coordinate: $0.coordinate, timestamp: $0.timestamp) }
        guard points.count >= 2 else { throw LoadError.missingGPS }
        if try await OutboxRepository.shared.hasUnsyncedReplayEvents(sessionId: sessionID) {
            throw LoadError.unsyncedEvents
        }
        var rows: [[String: Any]] = []
        var offset = 0
        var expectedCount: Int?
        while true {
            let response = try await SupabaseManager.shared.client.from("session_events")
                .select("id,created_at,address_id,building_id,event_type,metadata", count: .exact)
                .eq("session_id", value: sessionID.uuidString)
                .order("created_at", ascending: true)
                .order("id", ascending: true)
                .range(from: offset, to: offset + 999)
                .execute()
            guard let total = response.count,
                  expectedCount == nil || expectedCount == total,
                  let page = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else {
                throw LoadError.missingEvents
            }
            expectedCount = total
            rows.append(contentsOf: page)
            if rows.count == total { break }
            guard !page.isEmpty, rows.count < total else { throw LoadError.missingEvents }
            offset += page.count
        }
        let visits = try parseVisitRows(rows)
        if try await OutboxRepository.shared.hasUnsyncedReplayEvents(sessionId: sessionID) {
            throw LoadError.unsyncedEvents
        }
        guard let timeline = RecordedReplayTimeline(points: points, visits: visits) else { throw LoadError.missingGPS }
        return timeline
    }
    static func parseVisitRows(_ rows: [[String: Any]]) throws -> [RecordedReplayVisit] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let normal = ISO8601DateFormatter()
        let outcomeTypes: Set<String> = ["flyer_left", "conversation", "address_tap", "completed_manual", "completed_auto", "completion_undone"]
        let outcomeRows = rows.filter { outcomeTypes.contains($0["event_type"] as? String ?? "") }
        var visits: [RecordedReplayVisit] = []
        for row in outcomeRows {
            guard let rawDate = row["created_at"] as? String,
                  let date = fractional.date(from: rawDate) ?? normal.date(from: rawDate),
                  let eventType = row["event_type"] as? String else { throw LoadError.missingEvents }
            let metadata = row["metadata"] as? [String: Any] ?? [:]
            let status = eventType == "completion_undone" ? AddressStatus.none.rawValue : (metadata["address_status"] as? String ?? "")
            guard AddressStatus(rawValue: status) != nil else { throw LoadError.missingEvents }
            let primaryID = (row["address_id"] as? String).flatMap(UUID.init(uuidString:))
            var addressIDs: [UUID] = []
            if let rawIDs = metadata["campaign_address_ids"] {
                guard let values = rawIDs as? [String] else { throw LoadError.missingEvents }
                for value in values {
                    guard let id = UUID(uuidString: value) else { throw LoadError.missingEvents }
                    if !addressIDs.contains(id) { addressIDs.append(id) }
                }
            }
            if let primaryID, !addressIDs.contains(primaryID) {
                if metadata["campaign_address_ids"] != nil { throw LoadError.missingEvents }
                addressIDs.append(primaryID)
            }
            let buildingID = row["building_id"] as? String
            guard !addressIDs.isEmpty || buildingID != nil else { throw LoadError.missingEvents }
            if addressIDs.isEmpty {
                visits.append(RecordedReplayVisit(timestamp: date, addressID: nil, buildingID: buildingID, status: status))
            } else {
                for addressID in addressIDs {
                    visits.append(RecordedReplayVisit(timestamp: date, addressID: addressID, buildingID: buildingID, status: status))
                }
            }
        }
        guard !visits.isEmpty else { throw LoadError.missingEvents }
        var statusByTimestampAndTarget: [String: String] = [:]
        for visit in visits {
            let target = visit.addressID?.uuidString.lowercased() ?? visit.buildingID?.lowercased() ?? ""
            let key = "\(visit.timestamp.timeIntervalSince1970):\(target)"
            if let prior = statusByTimestampAndTarget[key], prior != visit.status {
                throw LoadError.missingEvents
            }
            statusByTimestampAndTarget[key] = visit.status
        }
        return visits
    }

}
