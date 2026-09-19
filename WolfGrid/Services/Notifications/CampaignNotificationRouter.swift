import Foundation
import UIKit
import UserNotifications

struct PendingCampaignRoute: Codable, Equatable {
    let campaignId: UUID
    let campaignName: String?
}

@MainActor
final class CampaignNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CampaignNotificationRouter()

    private var pendingCardRoute: BusinessCardPushRoute?
    private let pendingCardKey = "pending_business_card_push"
    private weak var uiState: AppUIState?
    private var pendingRoute: PendingCampaignRoute?
    private let pendingRouteKey = "pending_campaign_notification_route"

    private override init() {
        if let data = UserDefaults.standard.data(forKey: pendingRouteKey) {
            pendingRoute = try? JSONDecoder().decode(PendingCampaignRoute.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: pendingCardKey) { pendingCardRoute = try? JSONDecoder().decode(BusinessCardPushRoute.self, from: data) }
        super.init()
    }

    func configure(uiState: AppUIState) {
        self.uiState = uiState
        applyPendingRouteIfPossible()
    }

    func route(campaignId: UUID, campaignName: String?) {
        pendingRoute = PendingCampaignRoute(campaignId: campaignId, campaignName: campaignName)
        persistPendingRoute()
        applyPendingRouteIfPossible()
    }

    func applyPendingRouteIfPossible() {
        if let card = pendingCardRoute, let uiState, let user = AuthManager.shared.user {
            if user.id == card.userId { uiState.pendingBusinessCardActivity = card }
            pendingCardRoute = nil
            UserDefaults.standard.removeObject(forKey: pendingCardKey)
        }
        guard let pendingRoute, let uiState else { return }
        guard AuthManager.shared.user != nil else { return }
        Task {
            let isMapReady = await CampaignDownloadService.shared.ensureMapAssetsAvailable(
                campaignId: pendingRoute.campaignId.uuidString
            )
            guard isMapReady else { return }
            uiState.selectCampaign(id: pendingRoute.campaignId, name: pendingRoute.campaignName)
            uiState.selectedTabIndex = 1
            await CampaignDownloadService.shared.prefetchIfNeeded(campaignId: pendingRoute.campaignId.uuidString)
            self.pendingRoute = nil
            UserDefaults.standard.removeObject(forKey: pendingRouteKey)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        if userInfo["type"] as? String == "campaign_ready" {
            return []
        }
        return [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let route = BusinessCardPushRoute(userInfo: userInfo) {
            await MainActor.run {
                let router = CampaignNotificationRouter.shared
                router.pendingCardRoute = route
                if let data = try? JSONEncoder().encode(route) { UserDefaults.standard.set(data, forKey: router.pendingCardKey) }
                router.applyPendingRouteIfPossible()
            }
            return
        }
        guard userInfo["type"] as? String == "campaign_ready",
              let rawCampaignId = userInfo["campaign_id"] as? String,
              let campaignId = UUID(uuidString: rawCampaignId) else {
            return
        }
        let campaignName = userInfo["campaign_name"] as? String
        await MainActor.run {
            CampaignNotificationRouter.shared.route(campaignId: campaignId, campaignName: campaignName)
        }
    }

    private func persistPendingRoute() {
        guard let pendingRoute,
              let data = try? JSONEncoder().encode(pendingRoute) else {
            UserDefaults.standard.removeObject(forKey: pendingRouteKey)
            return
        }
        UserDefaults.standard.set(data, forKey: pendingRouteKey)
    }
}

@MainActor
final class FLYRAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = CampaignNotificationRouter.shared
        #if WOLFGRID_SALES
        SalespersonVoiceCallService.shared.start()
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistrationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistrationService.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}
