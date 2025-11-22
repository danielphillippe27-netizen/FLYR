import SwiftUI

struct MainTabView: View {
    @State private var campaignContext = CampaignContext()
    @EnvironmentObject var uiState: AppUIState
    @ObservedObject private var sessionManager = SessionManager.shared
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                // HOME (Campaigns with pager)
                NavigationStack {
                    HomePagerView()
                        .toolbar(uiState.showTabBar ? .automatic : .hidden, for: .tabBar)
                }
                .tabItem { Label("Home", systemImage: "house.fill") }

                // MAP
                NavigationStack {
                    FullScreenMapView()
                        .toolbar(uiState.showTabBar ? .automatic : .hidden, for: .tabBar)
                }
                .tabItem { Label("Map", systemImage: "map") }

                // QR CODES
                NavigationStack {
                    QRHomeView()
                        .toolbar(uiState.showTabBar ? .automatic : .hidden, for: .tabBar)
                }
                .tabItem { Label("QR", systemImage: "qrcode.viewfinder") }

                // CRM
                NavigationStack {
                    ContactsHubView()
                        .toolbar(uiState.showTabBar ? .automatic : .hidden, for: .tabBar)
                }
                .tabItem { Label("CRM", systemImage: "person.2.fill") }

                // STATS (unified Leaderboard + You)
                NavigationStack {
                    StatsPageView()
                        .toolbar(uiState.showTabBar ? .automatic : .hidden, for: .tabBar)
                }
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            }
            .tint(campaignContext.accentColor) // Apply dynamic accent color to tab bar
            .campaignContext(campaignContext) // Provide campaign context to all views
        }
        .onChange(of: sessionManager.isActive) { _, isActive in
            withAnimation(.easeInOut(duration: 0.25)) {
                uiState.showTabBar = !isActive
            }
        }
    }
}
