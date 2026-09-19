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
    private var lastUploadedIdentity: String?
    private var registrationGeneration = 0
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
        guard !isUploading, !AuthManager.shared.isUsingPasswordRecoverySession else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        guard let session = try? await client.auth.session,
              AuthManager.shared.user?.id == session.user.id else { return }
        if !UIApplication.shared.isRegisteredForRemoteNotifications {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            guard AuthManager.shared.user?.id == session.user.id,
                  !AuthManager.shared.isUsingPasswordRecoverySession else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }

        guard !isUploading, let token = pendingDeviceToken else { return }
        let identity = "\(session.user.id):\(token)"
        guard identity != lastUploadedIdentity else { return }
        let generation = registrationGeneration
        isUploading = true
        defer {
            isUploading = false
            Task {
                if let current = try? await client.auth.session,
                   current.user.id != session.user.id || generation != registrationGeneration || pendingDeviceToken != token {
                    await uploadPendingTokenIfPossible()
                }
            }
        }

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
                guard generation == registrationGeneration,
                      (try? await client.auth.session.user.id) == session.user.id,
                      AuthManager.shared.user?.id == session.user.id,
                      !AuthManager.shared.isUsingPasswordRecoverySession else {
                    request.httpMethod = "DELETE"
                    _ = try? await URLSession.shared.data(for: request)
                    return
                }
                lastUploadedIdentity = identity
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

    func unregisterBeforeSignOut() async {
        registrationGeneration += 1
        lastUploadedIdentity = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        guard let token = pendingDeviceToken,
              let session = try? await client.auth.session else { return }
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("api/devices/push-token"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(PushTokenRegistrationBody(token: token, platform: "ios", environment: Self.apnsEnvironment))
        _ = try? await URLSession.shared.data(for: request)
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static var apiBaseURL: URL {
        Config.backendAPIURL
    }
}

private struct PushTokenRegistrationBody: Encodable {
    let token: String
    let platform: String
    let environment: String
}
