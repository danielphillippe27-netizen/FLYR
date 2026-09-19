import Combine
import Foundation
import Supabase
import SwiftUI
import UIKit

/// Display presence only. Remote snapshots never enter CallKit or the local dialer queue.
@MainActor
final class SharedActiveCallService: ObservableObject {
    static let shared = SharedActiveCallService()
    @Published private(set) var calls: [SharedCallSnapshot] = []
    @Published private(set) var isUnavailable = false
    @Published private(set) var scope: String?
    private let deviceId = UUID().uuidString
    private var task: Task<Void, Never>?

    private var currentScope: String? {
        guard let user = AuthManager.shared.user?.id,
              let workspace = WorkspaceContext.shared.workspaceId else { return nil }
        return "\(user):\(workspace)"
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var hadLocalCall = false
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = SalespersonVoiceCallService.shared.sharedCallSnapshot
                if UIApplication.shared.applicationState == .active || snapshot != nil || hadLocalCall {
                    await self.sync(snapshot)
                    hadLocalCall = snapshot != nil
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    private func sync(_ call: SharedCallSnapshot?) async {
        let requestedScope = currentScope
        if scope != requestedScope {
            calls = []
            isUnavailable = false
            scope = requestedScope
        }
        guard let requestedScope,
              let workspaceId = WorkspaceContext.shared.workspaceId,
              let userId = AuthManager.shared.user?.id else { return }
        struct Payload: Encodable {
            let workspaceId: String
            let deviceId: String
            let platform = "ios"
            let call: SharedCallSnapshot?

            enum CodingKeys: String, CodingKey { case workspaceId, deviceId, platform, call }
            func encode(to encoder: Encoder) throws {
                var values = encoder.container(keyedBy: CodingKeys.self)
                try values.encode(workspaceId, forKey: .workspaceId)
                try values.encode(deviceId, forKey: .deviceId)
                try values.encode(platform, forKey: .platform)
                // Explicit null ends this device's presence; an omitted field is invalid.
                try values.encode(call, forKey: .call)
            }
        }
        struct Response: Decodable { let calls: [SharedCallSnapshot] }
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            guard session.user.id == userId, currentScope == requestedScope else { return }
            var request = URLRequest(url: Config.backendAPIURL.appendingPathComponent("api/dialer/active-call"))
            request.httpMethod = "PUT"
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(Payload(workspaceId: workspaceId.uuidString, deviceId: deviceId, call: call))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(Response.self, from: data)
            guard currentScope == requestedScope else { return }
            calls = result.calls
            isUnavailable = false
        } catch {
            guard currentScope == requestedScope else { return }
            isUnavailable = true
        }
    }
}

struct SharedActiveCallBanner: View {
    @ObservedObject private var sync = SharedActiveCallService.shared
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @ObservedObject private var voice = SalespersonVoiceCallService.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let scope = auth.user.flatMap { user in workspace.workspaceId.map { "\(user.id):\($0)" } }
            let calls = sync.scope == scope ? sync.calls.filter {
                (SharedCallSnapshot.date($0.expiresAt) ?? .distantPast) > timeline.date
            } : []
            if sync.scope == scope && sync.isUnavailable && (!calls.isEmpty || voice.sharedCallSnapshot != nil) {
                Text("Call sync unavailable. Your call can continue.")
                    .font(.caption).padding(10).frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            } else if !calls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(calls, id: \.deviceId) { call in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: call.platform == "ios" ? "iphone" : "desktopcomputer")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Calling on \(call.platform == "ios" ? "iPhone" : "web")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(call.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                if let phone = call.phone, phone != call.name {
                                    Text(phone).font(.caption)
                                }
                                HStack(spacing: 6) {
                                    Text(call.phase == "connected" ? "Connected" : "Connecting")
                                    if let date = SharedCallSnapshot.date(call.connectedAt) {
                                        Text(date, style: .timer).monospacedDigit()
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityElement(children: .contain)
            }
        }
    }
}
