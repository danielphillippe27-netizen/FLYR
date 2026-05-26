import Foundation
import Auth
import Supabase
import UIKit
import UserNotifications

@MainActor
final class PushRegistrationService {
    static let shared = PushRegistrationService()

    private let client = SupabaseManager.shared.client
    private var pendingDeviceToken: String?
    private var lastUploadedDeviceToken: String?
    private var isUploading = false

    private init() {}

    func requestCampaignReadyPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            #if DEBUG
            print("⚠️ [Push] Notification permission request failed: \(error.localizedDescription)")
            #endif
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        pendingDeviceToken = token
        Task { await uploadPendingTokenIfPossible() }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        #if DEBUG
        print("⚠️ [Push] Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
    }

    func uploadPendingTokenIfPossible() async {
        guard !isUploading else { return }
        guard let token = pendingDeviceToken, token != lastUploadedDeviceToken else { return }
        guard let session = try? await client.auth.session else { return }

        isUploading = true
        defer { isUploading = false }

        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("api/devices/push-token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(PushTokenRegistrationBody(
            token: token,
            platform: "ios",
            environment: Self.apnsEnvironment
        ))

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                lastUploadedDeviceToken = token
                #if DEBUG
                print("✅ [Push] Uploaded APNs token")
                #endif
            }
        } catch {
            #if DEBUG
            print("⚠️ [Push] APNs token upload failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static var apiBaseURL: URL {
        let url = Config.productionAppURL
        guard url.host == "flyrpro.app" else { return url }
        return URL(string: "https://www.flyrpro.app") ?? url
    }
}

private struct PushTokenRegistrationBody: Encodable {
    let token: String
    let platform: String
    let environment: String
}
