import Foundation

enum TelnyxPushPayload {
    static func isMissedCall(_ payload: [AnyHashable: Any]) -> Bool {
        guard let aps = payload["aps"] as? [String: Any],
              let alert = aps["alert"] else {
            return false
        }
        if let alert = alert as? String {
            return alert.caseInsensitiveCompare("Missed call!") == .orderedSame
        }
        if let alert = alert as? [String: Any],
           let body = alert["body"] as? String {
            return body.caseInsensitiveCompare("Missed call!") == .orderedSame
        }
        return false
    }

    static func callID(from payload: [AnyHashable: Any]) -> UUID? {
        guard let metadata = payload["metadata"] as? [String: Any],
              let rawCallID = metadata["call_id"] as? String else {
            return nil
        }
        return UUID(uuidString: rawCallID)
    }
}
