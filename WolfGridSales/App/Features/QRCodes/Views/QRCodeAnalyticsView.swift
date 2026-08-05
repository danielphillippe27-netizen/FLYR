import SwiftUI

/// QR Code Analytics Screen
/// Orchestrates hook + components only
struct QRCodeAnalyticsView: View {
    @StateObject private var hook = UseQRCodeAnalytics()
    
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
                                await hook.loadScansForCampaign(campaignId)
                            }
                        }
                    )
                }
                
                Divider()
                
                // Address Filter (optional)
                if let campaignId = hook.selectedCampaignId {
                    AddressFilter(
                        addresses: hook.addresses,
                        selectedId: hook.selectedAddressId,
                        onSelectAll: {
                            Task {
                                await hook.loadScansForCampaign(campaignId)
                            }
                        },
                        onSelectAddress: { addressId in
                            Task {
                                await hook.loadScansForAddress(addressId)
                            }
                        }
                    )
                }
                
                Divider()
                
                // Analytics Content
                if hook.isLoading {
                    ProgressView("Loading analytics...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hook.selectedCampaignId == nil {
                    EmptyState(
                        illustration: "chart.bar.fill",
                        title: "Select a Campaign",
                        message: "Choose a campaign to view analytics"
                    )
                } else if let summary = hook.summary {
                    ScrollView {
                        VStack(spacing: 20) {
                            QRAnalyticsCard(summary: summary)
                                .padding(.horizontal)
                            
                            if !summary.recentScans.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Recent Scans")
                                        .font(.flyrTitle2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal)
                                    
                                    ForEach(summary.recentScans) { scan in
                                        QRScanItem(scan: scan)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationTitle("Analytics")
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

