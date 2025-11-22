import SwiftUI

/// Landing Page Management Screen
/// Orchestrates hook + components only
struct QRCodeLandingView: View {
    @StateObject private var hook = UseQRCodeLanding()
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Campaign Selector
                if hook.isLoadingCampaigns {
                    ProgressView()
                        .padding()
                } else {
                    CampaignSelector(
                        campaigns: hook.campaigns,
                        selectedId: hook.selectedCampaignId,
                        onSelect: { campaignId in
                            Task {
                                await hook.loadAddressesForCampaign(campaignId)
                            }
                        }
                    )
                }
                
                Divider()
                
                // Address Selector
                if let campaignId = hook.selectedCampaignId {
                    AddressSelector(
                        addresses: hook.addresses,
                        selectedId: hook.selectedAddressId,
                        isLoading: hook.isLoading,
                        onSelect: { addressId in
                            Task {
                                await hook.loadContentForAddress(addressId)
                            }
                        }
                    )
                }
                
                Divider()
                
                // Content Editor
                if let addressId = hook.selectedAddressId {
                    if hook.isLoading {
                        ProgressView("Loading content...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let content = hook.addressContent {
                        LandingPageContentEditor(
                            content: content,
                            isSaving: hook.isSaving,
                            onSave: { updatedContent in
                                Task {
                                    await hook.saveContent(updatedContent)
                                }
                            }
                        )
                    }
                } else {
                    EmptyState(
                        illustration: "globe",
                        title: "Select an Address",
                        message: "Choose an address to configure its landing page"
                    )
                }
            }
        }
        .navigationTitle("Landing Page")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await hook.loadCampaigns()
        }
        .alert("Error", isPresented: Binding(
            get: { hook.errorMessage != nil },
            set: { if !$0 { hook.errorMessage = nil } }
        )) {
            Button("OK") {
                hook.errorMessage = nil
            }
        } message: {
            if let error = hook.errorMessage {
                Text(error)
            }
        }
    }
}

