import Foundation

// Run with SharedCallSnapshot.swift to check the native/API wire contract.
@main
struct SharedCallPayloadTest {
    static func main() throws {
        let snapshot = SharedCallSnapshot(
            id: "test-call", name: "Jamie Example", phone: nil,
            phase: "connecting", startedAt: "2026-09-09T15:00:00Z", connectedAt: nil
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(json["phone"] is NSNull, "phone must encode as null, not disappear")
        precondition(json["connectedAt"] is NSNull, "connecting calls must include connectedAt: null")
        precondition(SharedCallSnapshot.date(snapshot.startedAt) != nil)
        precondition(SharedCallSnapshot.date("2026-09-09T15:00:00.123Z") != nil)
        let response = Data("""
        {"id":"test-call","name":"Jamie Example","phone":"+14165550123","phase":"connected","startedAt":"2026-09-09T15:00:00Z","connectedAt":"2026-09-09T15:00:02.000Z","deviceId":"web-device","platform":"web","expiresAt":"2026-09-09T15:01:30.000Z"}
        """.utf8)
        let decoded = try JSONDecoder().decode(SharedCallSnapshot.self, from: response)
        precondition(decoded.platform == "web")
        precondition(decoded.phone == "+14165550123")
        precondition(SharedCallSnapshot.date(decoded.expiresAt) != nil)
        print("Shared call Swift payload checks passed")
    }
}
