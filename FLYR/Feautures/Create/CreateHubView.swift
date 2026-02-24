import SwiftUI
import Supabase

struct CreateHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @StateObject private var storeV2 = CampaignV2Store.shared
    
    @State private var navigateToCampaign = false
    @State private var navigateToFarm = false
    @State private var showPaywall = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 24) {
                    ForEach(CreateHubOption.allCases) { option in
                        Button {
                            handleTap(option)
                        } label: {
                            Text(option.title)
                                .font(.flyrSystem(size: 28, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.primary)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .scaleEffectOnTap()
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .onAppear { 
            uiState.showTabBar = false 
        }
        .onDisappear { 
            uiState.showTabBar = true 
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToCampaign) {
            NewCampaignScreen(store: storeV2)
        }
        .sheet(isPresented: $navigateToFarm) {
            NavigationStack {
                CreateFarmView()
                    .environmentObject(AuthManager.shared)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    private func handleTap(_ option: CreateHubOption) {
        switch option {
        case .campaign:
            Task {
                let canCreate = await canCreateCampaignInCurrentPlan()
                await MainActor.run {
                    if canCreate {
                        navigateToCampaign = true
                    } else {
                        showPaywall = true
                    }
                }
            }
        case .farm:
            navigateToFarm = true
        }
    }

    private func canCreateCampaignInCurrentPlan() async -> Bool {
        if entitlementsService.canUsePro {
            return true
        }
        if !storeV2.campaigns.isEmpty {
            return false
        }
        let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId)
        do {
            let campaigns = try await CampaignsAPI.shared.fetchCampaignsMetadata(workspaceId: workspaceId)
            return campaigns.isEmpty
        } catch {
            return storeV2.campaigns.isEmpty
        }
    }
}

enum CreateHubOption: String, CaseIterable, Identifiable {
    case campaign, farm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .campaign: "Campaign"
        case .farm: "Farm"
        }
    }
}

#Preview {
    NavigationStack {
        CreateHubView()
            .environmentObject(AppUIState())
    }
}



