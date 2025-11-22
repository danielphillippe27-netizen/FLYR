import SwiftUI

struct HomePagerView: View {
  @State private var section: HomeSection = .campaigns
  @State private var selectedCampaignID: UUID?
  @State private var showCreateHub = false
  @State private var showSettings = false
  @StateObject private var storeV2 = CampaignV2Store.shared
  @EnvironmentObject private var uiState: AppUIState

  var body: some View {
    NavigationStack {
      TabView(selection: $section) {
        CampaignsListView()
          .tag(HomeSection.campaigns)
        FarmListView()
          .tag(HomeSection.farm)
          .environmentObject(AuthManager.shared)
        FLYRHomeView()
          .tag(HomeSection.flyr)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))   // ← swipe only
      .navigationTitle("") // Empty to hide default title
      .toolbar {
        // Interactive header menu
        ToolbarItem(placement: .principal) {
          Menu {
            ForEach(HomeSection.allCases) { sectionOption in
              Button(sectionOption.title) {
                withAnimation(.easeInOut(duration: 0.2)) {
                  section = sectionOption
                }
              }
            }
          } label: {
            HStack(spacing: 4) {
              Text(section.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.text)
              Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundColor(.text)
            }
          }
        }
        // Red + button to create campaign/farm - moved to leading
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            showCreateHub = true
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.red)
          }
        }
        // Settings button on the right
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.text)
          }
        }
      }
      .navigationDestination(item: $selectedCampaignID) { campaignID in
        NewCampaignDetailView(campaignID: campaignID, store: storeV2)
      }
      .sheet(isPresented: $showCreateHub) {
        NavigationStack {
          CreateHubView()
            .environmentObject(uiState)
        }
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
      }
      .onAppear {
        // Set up the navigation callback
        storeV2.routeToV2Detail = { campaignID in
          selectedCampaignID = campaignID
        }
      }
      .animation(.easeInOut(duration: 0.2), value: section)
    }
  }
}

#Preview {
    NavigationStack {
        HomePagerView()
            .navigationTitle("Home")
    }
}

