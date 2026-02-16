import SwiftUI
import UIKit
import MapboxMaps
import Supabase
@main
struct FLYRApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var uiState = AppUIState()
    @StateObject private var entitlementsService = EntitlementsService()

    init() {
        MapboxOptions.accessToken = Config.mapboxAccessToken
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

    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environmentObject(uiState)
                .environmentObject(entitlementsService)
                .task {
                    // Health check in background with lower priority - don't block UI
                    Task.detached(priority: .utility) {
                        #if DEBUG
                        print("🏥 Initializing address service health check in background...")
                        #endif
                        await AddressServiceHealth.shared.checkHealth(lat: 43.987854, lon: -78.622448)
                    }
                }
                .onOpenURL { url in
                    Task {
                        #if DEBUG
                        print("🔗 Received URL: \(url)")
                        #endif
                        // Handle OAuth redirects for CRM integrations only
                        if url.scheme == "flyr" && url.host == "oauth" {
                            await handleOAuthRedirect(url: url)
                        }
                    }
                }
        }
    }
    
    // MARK: - OAuth Redirect Handler
    
    private func handleOAuthRedirect(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            print("⚠️ Invalid OAuth redirect URL")
            return
        }
        
        // Extract provider and code from URL
        let providerString = queryItems.first(where: { $0.name == "provider" })?.value
        let code = queryItems.first(where: { $0.name == "code" })?.value
        
        guard let providerString = providerString,
              let code = code,
              let provider = IntegrationProvider(rawValue: providerString),
              let userId = AuthManager.shared.user?.id else {
            print("⚠️ Missing OAuth parameters")
            return
        }
        
        // Complete OAuth flow
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
}

struct AuthGate: View {
    @StateObject private var auth = AuthManager.shared
    @EnvironmentObject var uiState: AppUIState
    @EnvironmentObject var entitlementsService: EntitlementsService
    @Environment(\.scenePhase) private var scenePhase

    private var showMainApp: Bool {
        auth.user != nil
    }

    var body: some View {
        Group {
            if showMainApp {
                MainTabView()
            } else {
                SignInView()
            }
        }
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

            if let userId = auth.user?.id {
                await uiState.loadAppearancePreference(userID: userId)
                StoreKitManager.shared.entitlementsService = entitlementsService
                await entitlementsService.fetchEntitlement()
                await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
            } else if uiState.colorScheme == nil {
                uiState.detectSystemAppearance()
            }
        }
        .onChange(of: auth.user?.id) { _, newUserId in
            if let userId = newUserId {
                Task {
                    await uiState.loadAppearancePreference(userID: userId)
                    StoreKitManager.shared.entitlementsService = entitlementsService
                    await entitlementsService.fetchEntitlement()
                    await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
                }
            } else {
                uiState.detectSystemAppearance()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, auth.user != nil {
                Task {
                    await entitlementsService.fetchEntitlement()
                }
            }
        }
    }
}
