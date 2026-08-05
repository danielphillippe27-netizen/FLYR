import SwiftUI
import UIKit
import MapboxMaps
import GoogleMaps
import Supabase
import CoreLocation
@main
struct WolfGridApp: App {
    @UIApplicationDelegateAdaptor(FLYRAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthManager.shared
    @StateObject private var uiState = AppUIState()
    @StateObject private var entitlementsService = EntitlementsService()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var offlineSyncCoordinator = OfflineSyncCoordinator.shared
    @StateObject private var campaignDownloadService = CampaignDownloadService.shared
    @StateObject private var offlinePreloadCoordinator = OfflinePreloadCoordinator.shared

    init() {
        let mapboxToken = Config.mapboxAccessToken
        if !mapboxToken.isEmpty {
            MapboxOptions.accessToken = mapboxToken
        }
        let googleMapsAPIKey = Config.googleMapsAPIKey
        if !googleMapsAPIKey.isEmpty {
            let didProvideGoogleMapsKey = GMSServices.provideAPIKey(googleMapsAPIKey)
            #if DEBUG
            if !didProvideGoogleMapsKey {
                print("⚠️ [GoogleMaps] Failed to register Google Maps API key for this build.")
            }
            #endif
        } else {
            #if DEBUG
            print("⚠️ [GoogleMaps] GOOGLE_MAPS_API_KEY is missing or unresolved in Info.plist.")
            #endif
        }
        _ = OfflineDatabase.shared
        NetworkMonitor.shared.startIfNeeded()
        _ = OfflineSyncCoordinator.shared
        _ = CampaignDownloadService.shared
        _ = OfflinePreloadCoordinator.shared
        #if DEBUG
        Self.verifyInterFonts()
        #endif
    }

    #if DEBUG
    private static func verifyInterFonts() {
        let names = ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"]
        let available = UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }
        print("🔤 Loaded font names (Inter): \(available.filter { $0.contains("Inter") })")
        var allFound = true
        for name in names {
            if UIFont(name: name, size: 17) == nil {
                print("⚠️ Inter font missing: \(name)")
                allFound = false
            }
        }
        if !allFound {
            AppFont.isInterEnabled = false
            print("⚠️ Inter disabled; using system fonts.")
        }
    }
    #endif

    @StateObject private var routeState = AppRouteState()

    var body: some Scene {
        WindowGroup {
            AuthGate(routeState: routeState)
                .environmentObject(uiState)
                .environmentObject(entitlementsService)
                .environmentObject(routeState)
                .environmentObject(networkMonitor)
                .environmentObject(offlineSyncCoordinator)
                .environmentObject(campaignDownloadService)
                .environmentObject(offlinePreloadCoordinator)
                .task {
                    // Health check in background with lower priority - don't block UI
                    Task.detached(priority: .utility) {
                        #if DEBUG
                        print("🏥 Initializing address service health check in background...")
                        #endif
                        await AddressServiceHealth.shared.checkHealth(lat: 43.987854, lon: -78.622448)
                    }
                    offlineSyncCoordinator.scheduleProcessOutbox()
                    offlinePreloadCoordinator.schedule(reason: "app_task")
                }
                .onChange(of: networkMonitor.isOnline) { isOnline in
                    if isOnline {
                        offlineSyncCoordinator.scheduleProcessOutbox()
                        offlinePreloadCoordinator.schedule(reason: "network_online")
                    }
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    offlinePreloadCoordinator.schedule(reason: "foreground")
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        await handleIncomingURL(url)
                    }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { @MainActor in
                        await handleIncomingURL(url)
                    }
                }
        }
    }
    
    // MARK: - OAuth Redirect Handler
    
    private func handleOAuthRedirect(url: URL) async {
        guard NetworkMonitor.shared.isOnline else {
            #if DEBUG
            print("⚠️ OAuth redirect received while offline; reconnect before completing integration refresh.")
            #endif
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("⚠️ Invalid OAuth redirect URL")
            return
        }
        
        let providerRaw = queryItems.first(where: { $0.name == "provider" })?.value
        let code = queryItems.first(where: { $0.name == "code" })?.value
        let status = queryItems.first(where: { $0.name == "status" })?.value
        let message = queryItems.first(where: { $0.name == "message" })?.value

        #if DEBUG
        print("🔗 [OAuth Redirect] provider=\(providerRaw ?? "nil") status=\(status ?? "nil") codePresent=\(code != nil) message=\(message ?? "nil") url=\(url.absoluteString)")
        #endif

        guard let providerRaw else {
            print("⚠️ Missing OAuth provider")
            return
        }

        if providerRaw == "fub" {
            guard let userId = AuthManager.shared.user?.id else {
                print("⚠️ FUB OAuth callback received without signed-in user")
                return
            }
            if status == "success" {
                await CRMConnectionStore.shared.refresh(userId: userId)
                #if DEBUG
                let refreshedConnection = CRMConnectionStore.shared.fubConnection
                print("✅ OAuth flow completed for Follow Up Boss. connected=\(refreshedConnection?.isConnected == true) status=\(refreshedConnection?.status ?? "nil") errorReason=\(refreshedConnection?.errorReason ?? "nil") storeError=\(CRMConnectionStore.shared.error ?? "nil")")
                #else
                print("✅ OAuth flow completed for Follow Up Boss")
                #endif
            } else {
                print("❌ OAuth flow failed for Follow Up Boss: \(message ?? "Unknown error")")
            }
            return
        }

        if providerRaw == "monday", let status {
            if status == "success" {
                print("✅ OAuth flow completed for Monday.com")
            } else {
                print("❌ OAuth flow failed for Monday.com: \(message ?? "Unknown error")")
            }
            return
        }

        if providerRaw == "hubspot", let status {
            if status == "success" {
                print("✅ OAuth flow completed for HubSpot")
            } else {
                print("❌ OAuth flow failed for HubSpot: \(message ?? "Unknown error")")
            }
            return
        }

        guard let code,
              let provider = IntegrationProvider(rawValue: providerRaw),
              let userId = AuthManager.shared.user?.id else {
            print("⚠️ Missing OAuth parameters")
            return
        }

        // Monday.com still exchanges the authorization code via Supabase Edge Function.
        guard provider == .monday else {
            print("⚠️ Unexpected OAuth code callback for provider \(providerRaw)")
            return
        }

        do {
            try await CRMIntegrationManager.shared.completeOAuthFlow(
                provider: provider,
                code: code,
                userId: userId
            )
            print("✅ OAuth flow completed for \(provider.displayName)")
        } catch {
            print("❌ OAuth flow failed: \(error.localizedDescription)")
        }
    }

    private func handleIncomingURL(_ url: URL) async {
        #if DEBUG
        print("🔗 Received URL: \(url)")
        #endif

        if Config.matchesPasswordRecoveryURL(url) {
            await handlePasswordRecoveryRedirect(url: url)
            return
        }

        let nativeSchemes: Set<String> = ["flyr", "wolfgrid", "wolfgridsales"]
        let scheme = url.scheme?.lowercased() ?? ""

        if nativeSchemes.contains(scheme) && url.host == "oauth" {
            await handleOAuthRedirect(url: url)
            return
        }

        if nativeSchemes.contains(scheme), url.host == "salesperson", url.path == "/leads" {
            uiState.selectedTabIndex = 2
            return
        }

        if let token = inviteToken(from: url) {
            routeState.pendingJoinToken = token
            routeState.pendingChallengeToken = nil
            await routeState.resolveRoute()
            return
        }

        if let token = challengeToken(from: url) {
            routeState.pendingChallengeToken = token
            routeState.pendingJoinToken = nil
            await routeState.resolveRoute()
        }
    }

    private func handlePasswordRecoveryRedirect(url: URL) async {
        routeState.presentPasswordReset(state: .awaitingLink)

        do {
            let recoveredEmail = try await auth.activatePasswordRecovery(from: url)
            routeState.presentPasswordReset(
                state: .ready(email: recoveredEmail),
                emailHint: recoveredEmail
            )
        } catch {
            routeState.presentPasswordReset(
                state: .invalid(message: error.localizedDescription),
                emailHint: routeState.passwordResetEmailHint
            )
        }
    }

    private func inviteToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value

        if ["flyr", "wolfgrid"].contains(url.scheme?.lowercased() ?? "") && url.host == "join" {
            return token
        }

        if (url.scheme == "https" || url.scheme == "http"),
           ["wolfgrid.app", "www.wolfgrid.app", "flyrpro.app", "www.flyrpro.app", "flyr.software", "www.flyr.software"].contains(url.host?.lowercased() ?? ""),
           url.path == "/join" {
            return token
        }

        return nil
    }

    private func challengeToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value

        if ["flyr", "wolfgrid"].contains(url.scheme?.lowercased() ?? "") && url.host == "challenge" {
            return token
        }

        if (url.scheme == "https" || url.scheme == "http"),
           ["wolfgrid.app", "www.wolfgrid.app", "flyrpro.app", "www.flyrpro.app", "flyr.software", "www.flyr.software"].contains(url.host?.lowercased() ?? ""),
           url.path == "/challenges/join" {
            return token
        }

        return nil
    }
}

struct AuthGate: View {
    @ObservedObject var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared
    @EnvironmentObject var uiState: AppUIState
    @EnvironmentObject var entitlementsService: EntitlementsService
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var e2ePresencePublished = false
    @State private var e2ePresenceError: String?
    #endif

    var body: some View {
        Group {
            switch routeState.route {
            case .login:
                SignInView()
            case .passwordReset:
                ResetPasswordView()
            case .onboarding:
                WorkspaceOnboardingView()
            case .join(let token):
                JoinFlowView(token: token)
            case .challengeInvite(let token):
                NavigationStack {
                    ChallengeInviteView(token: token)
                }
            case .subscribe(let memberInactive):
                PaywallView(memberInactive: memberInactive)
                    .environmentObject(entitlementsService)
            case .dashboard:
                #if WOLFGRID_SALES
                SalespersonMainTabView()
                #else
                MainTabView()
                #endif
            }
        }
        .accessibilityIdentifier(routeAccessibilityIdentifier)
        .preferredColorScheme(uiState.colorScheme)
        .onAppear {
            if uiState.colorScheme == nil {
                uiState.detectSystemAppearance()
            }
        }
        .task {
            #if DEBUG
            print("🔍 Loading session in background...")
            #endif
            await auth.loadSession()
            await routeState.resolveRoute()

            if let userId = auth.user?.id {
                await uiState.loadAppearancePreference(userID: userId)
                await PushRegistrationService.shared.uploadPendingTokenIfPossible()
                CampaignNotificationRouter.shared.applyPendingRouteIfPossible()
                _ = await entitlementsService.fetchEntitlement()
            } else if uiState.colorScheme == nil {
                uiState.detectSystemAppearance()
            }
        }
        .onChange(of: auth.user?.id) { _, newUserId in
            if newUserId == nil {
                Task { @MainActor in
                    await routeState.resolveRoute()
                }
            } else {
                Task { @MainActor in
                    guard let userId = newUserId else { return }
                    // Brief delay so Supabase session is fully available before calling redirect API
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    await routeState.resolveRoute()
                    await uiState.loadAppearancePreference(userID: userId)
                    await PushRegistrationService.shared.uploadPendingTokenIfPossible()
                    CampaignNotificationRouter.shared.applyPendingRouteIfPossible()
                    _ = await entitlementsService.fetchEntitlement()
                    #if DEBUG
                    print("🔍 [AuthGate] After sign-in resolveRoute → route: \(routeState.route)")
                    #endif
                }
            }
            if newUserId == nil, uiState.colorScheme == nil {
                uiState.detectSystemAppearance()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, auth.user != nil {
                Task {
                    await routeState.resolveRoute()
                    await PushRegistrationService.shared.uploadPendingTokenIfPossible()
                    CampaignNotificationRouter.shared.applyPendingRouteIfPossible()
                    _ = await entitlementsService.fetchEntitlement()
                }
            }
        }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            if hasE2EPresenceConfiguration, !e2ePresencePublished {
                VStack(alignment: .trailing, spacing: 8) {
                    if let e2ePresenceError {
                        Text(e2ePresenceError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("e2e.presence.error")
                    }
                    Button("Publish E2E presence") {
                        Task { await publishE2EPresenceIfConfigured() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 180, minHeight: 44)
                    .accessibilityIdentifier("e2e.publish.presence")
                }
                .padding()
                .zIndex(999)
            } else if e2ePresencePublished {
                Text("E2E presence published")
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("e2e.presence.published")
            }
        }
        #endif
    }

    private var routeAccessibilityIdentifier: String {
        switch routeState.route {
        case .login: return "route.login"
        case .passwordReset: return "route.passwordReset"
        case .onboarding: return "route.onboarding"
        case .join: return "route.join"
        case .challengeInvite: return "route.challengeInvite"
        case .subscribe: return "route.subscribe"
        case .dashboard: return "route.dashboard"
        }
    }

    #if DEBUG
    private var hasE2EPresenceConfiguration: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["WOLFGRID_E2E"] == "1"
            && environment["WOLFGRID_E2E_CAMPAIGN_ID"] != nil
            && environment["WOLFGRID_E2E_SESSION_ID"] != nil
    }

    @MainActor
    private func publishE2EPresenceIfConfigured() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WOLFGRID_E2E"] == "1",
              SupabaseManager.shared.isLocalE2E,
              let userId = auth.user?.id,
              let campaignId = UUID(uuidString: environment["WOLFGRID_E2E_CAMPAIGN_ID"] ?? ""),
              let sessionId = UUID(uuidString: environment["WOLFGRID_E2E_SESSION_ID"] ?? ""),
              let latitude = Double(environment["WOLFGRID_E2E_LATITUDE"] ?? ""),
              let longitude = Double(environment["WOLFGRID_E2E_LONGITUDE"] ?? "") else { return }
        do {
            e2ePresenceError = nil
            try await SharedLiveCanvassingService.shared.publishE2EPresence(
                campaignId: campaignId,
                sessionId: sessionId,
                userId: userId,
                location: CLLocation(latitude: latitude, longitude: longitude)
            )
            e2ePresencePublished = true
            NSLog("WolfGrid E2E presence publish succeeded")
        } catch {
            e2ePresenceError = error.localizedDescription
            NSLog("WolfGrid E2E presence publish failed: %@", error.localizedDescription)
        }
    }
    #endif
}
