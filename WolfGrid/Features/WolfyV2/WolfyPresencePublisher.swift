import Foundation
import CoreLocation
import Combine
import Supabase

/// Reuses accepted session fixes. It never starts, reconfigures or samples GPS itself.
@MainActor final class WolfyPresencePublisherV2 {
    static let shared = WolfyPresencePublisherV2()
    private struct Runtime: Decodable { let version: Int; let pack_enabled: Bool }
    private struct Scope: Equatable { let user: UUID; let campaign: UUID; let session: UUID }
    private let client = SupabaseManager.shared.client
    private var scope: Scope?
    private var cachedRuntime: Runtime?
    private var runtimeAt = Date.distantPast
    private var lastLocation: CLLocation?
    private var lastPaused = false
    private var lastFixSent: Date?
    private var lastPublish = Date.distantPast
    private var lastHeartbeat = Date.distantPast
    private var busy = false
    private var authObservation: AnyCancellable?
    private init() {
        authObservation = AuthManager.shared.$user.sink { [weak self] user in
            guard let self, let scope = self.scope, scope.user != user?.id else { return }
            self.clear(user: scope.user, campaign: scope.campaign)
        }
    }

    func clear(user: UUID?, campaign: UUID?) {
        guard scope?.user == user, scope?.campaign == campaign else { return }
        scope = nil; lastLocation = nil; lastFixSent = nil; cachedRuntime = nil
    }

    /// True means the v2 path owns this update, including denied or failed updates.
    /// Legacy writes are allowed only when the server flag is off or its RPC is absent.
    func handle(campaign: UUID, session: UUID, user: UUID, location: CLLocation?, paused: Bool) async -> Bool {
        let nextScope = Scope(user: user, campaign: campaign, session: session)
        if busy { return true }
        busy = true
        defer { busy = false }
        if scope != nextScope {
            scope = nextScope; cachedRuntime = nil; runtimeAt = .distantPast
            lastLocation = nil; lastPaused = false; lastFixSent = nil; lastPublish = .distantPast; lastHeartbeat = .distantPast
        }
        do {
            guard try await client.auth.session.user.id == user else { return true }
            if cachedRuntime == nil || Date().timeIntervalSince(runtimeAt) >= 30 {
                let response = try await client.rpc("wolfy_v2_runtime").execute()
                guard scope == nextScope else { return true }
                cachedRuntime = try JSONDecoder().decode(Runtime.self, from: response.data)
                runtimeAt = Date()
            }
            guard cachedRuntime?.version == 2 else { return true }
            guard cachedRuntime?.pack_enabled == true else { return false }
            guard try await client.auth.session.user.id == user else { return true }
            if paused {
                if lastPaused { return true }
                struct Params: Encodable { let p_campaign: UUID; let p_session: UUID }
                _ = try await client.rpc("wolfy_pack_clear_presence", params: Params(p_campaign: campaign, p_session: session)).execute()
                guard scope == nextScope else { return true }
                lastPaused = true; lastLocation = nil; lastFixSent = nil; lastPublish = .distantPast; lastHeartbeat = .distantPast
                return true
            }
            lastPaused = false
            let now = Date()
            let usable = location.map {
                CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 &&
                now.timeIntervalSince($0.timestamp) >= -5 && now.timeIntervalSince($0.timestamp) < 60 && $0.speed <= 12
            } ?? false
            let activity = usable && (location?.speed ?? 0) >= 0.35 ? "moving" : "idle"
            let moved = location.map { next in lastLocation.map { next.distance(from: $0) >= 3 } ?? true } ?? false
            let interval: TimeInterval = activity == "moving" || moved ? 5 : 30
            if let location, usable, location.timestamp > (lastFixSent ?? .distantPast), now.timeIntervalSince(lastPublish) >= interval {
                struct Params: Encodable {
                    let p_campaign: UUID; let p_session: UUID
                    let p_lat: Double; let p_lng: Double; let p_fixed_at: Date; let p_accuracy: Double
                    let p_heading: Double?; let p_speed: Double; let p_sequence: Int64; let p_activity: String
                }
                let response = try await client.rpc("wolfy_pack_publish", params: Params(
                    p_campaign: campaign, p_session: session, p_lat: location.coordinate.latitude, p_lng: location.coordinate.longitude,
                    p_fixed_at: location.timestamp, p_accuracy: location.horizontalAccuracy,
                    p_heading: location.course >= 0 && location.course < 360 ? location.course : nil,
                    p_speed: max(0, location.speed), p_sequence: Int64(location.timestamp.timeIntervalSince1970 * 1_000_000),
                    p_activity: activity)).execute()
                guard scope == nextScope else { return true }
                lastPublish = now
                if (try? JSONDecoder().decode(Bool.self, from: response.data)) == true {
                    lastLocation = location; lastFixSent = location.timestamp; lastHeartbeat = now
                }
            } else if now.timeIntervalSince(lastHeartbeat) >= 30 {
                struct Params: Encodable { let p_campaign: UUID; let p_session: UUID; let p_activity: String }
                _ = try await client.rpc("wolfy_pack_heartbeat", params: Params(p_campaign: campaign, p_session: session, p_activity: activity)).execute()
                guard scope == nextScope else { return true }
                lastHeartbeat = now
            }
            return true
        } catch let error as PostgrestError where error.code == "PGRST202" || error.code == "42883" {
            // An older deployment has no v2 interfaces yet. Do not mask authorization/network errors this way.
            guard scope == nextScope else { return true }
            if cachedRuntime?.pack_enabled == true { return true }
            cachedRuntime = Runtime(version: 2, pack_enabled: false); runtimeAt = Date()
            return false
        } catch {
            return true
        }
    }
}
