import Foundation
// Minimal unrelated home-state dependency for this standalone macOS reducer test.
struct AddressStatusRow { let addressId: UUID; let revision: Int; let updatedAt: Date }
@main struct WolfyPresenceCompatibilityTest {
 static func main() throws {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let campaign = UUID(), user = UUID(), session = UUID()
  var payload: [String: Any] = ["campaign_id":campaign.uuidString,"user_id":user.uuidString,"session_id":session.uuidString,
   "lat":43.0,"lng": -79.0,"updated_at":now.timeIntervalSince1970,"status":"active"]
  let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
  func decode() throws -> CampaignPresenceRow { try decoder.decode(CampaignPresenceRow.self, from: JSONSerialization.data(withJSONObject: payload)) }
  func render(_ row: CampaignPresenceRow) -> [SharedCanvassingTeammate] {
   SharedLiveCanvassingReducer.teammates(from: [user:row], directory: [:], currentUserId: nil, currentSessionId: nil, now: now)
  }
  let legacy = try decode()
  assert(render(legacy).first?.freshness == .live, "Legacy payload compatibility")
  payload["location_fixed_at"] = now.addingTimeInterval(-70).timeIntervalSince1970
  let stale = try decode()
  assert(stale.updatedAt == now, "Keep actual heartbeat independently")
  assert(render(stale).first?.freshness == .stale, "Fresh heartbeat must not freshen coordinates")
  assert(render(stale).first?.updatedAt == now.addingTimeInterval(-70), "Last seen reflects GPS fix")
  payload["location_fixed_at"] = now.addingTimeInterval(-180).timeIntervalSince1970
  let expired = try decode()
  assert(render(expired).isEmpty, "Remove coordinates at 180 seconds")
  print("PASS: legacy presence decode; independent heartbeat/fix age; stale and expired map markers")
 }
}
