import SwiftUI
import MapboxMaps
import Supabase
import Auth

@main
struct FLYRApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var uiState = AppUIState()
    
    init() {
        MapboxOptions.accessToken = Config.mapboxAccessToken
    }
    
    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environmentObject(uiState)
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
                        
                        // Handle OAuth redirects for CRM integrations
                        if url.scheme == "flyr" && url.host == "oauth" {
                            await handleOAuthRedirect(url: url)
                        } else {
                            // Handle auth URLs (magic link, etc.)
                            await auth.handleAuthURL(url)
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
    
    var body: some View {
        Group {
            if auth.user != nil {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .preferredColorScheme(uiState.colorScheme) // Apply color scheme
        .onAppear {
            // Detect system appearance immediately on app launch
            if uiState.colorScheme == nil {
                uiState.detectSystemAppearance()
            }
        }
        // Session loads in background - UI already rendered above
        .task {
            // Non-blocking: UI already rendered, this just updates state when ready
            #if DEBUG
            print("🔍 Loading session in background...")
            #endif
            await auth.loadSession()
            
            // Load appearance preference when user is logged in
            if let userId = auth.user?.id {
                await uiState.loadAppearancePreference(userID: userId)
            } else {
                // No user logged in, ensure system appearance is detected
                if uiState.colorScheme == nil {
                    uiState.detectSystemAppearance()
                }
            }
        }
        .onChange(of: auth.user?.id) { newUserId in
            if let userId = newUserId {
                Task {
                    await uiState.loadAppearancePreference(userID: userId)
                }
            } else {
                // User logged out, detect system appearance
                uiState.detectSystemAppearance()
            }
        }
    }
}
