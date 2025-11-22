import SwiftUI

/// QR Code Management Screen
/// Orchestrates hook + components only
struct QRCodeManageView: View {
    @StateObject private var hook = UseQRCodeManage()
    @State private var selectedQRCode: QRCodeAddress?
    
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
                                await hook.loadQRCodesForCampaign(campaignId)
                            }
                        }
                    )
                }
                
                Divider()
                
                // QR Codes List
                if hook.isLoading {
                    ProgressView("Loading QR codes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hook.qrCodes.isEmpty {
                    EmptyState(
                        illustration: "qrcode",
                        title: "No QR Codes",
                        message: hook.selectedCampaignId == nil 
                            ? "Select a campaign to view QR codes"
                            : "No QR codes found for this campaign"
                    )
                } else {
                    QRCodeList(
                        qrCodes: hook.qrCodes,
                        onQRCodeTap: { qrCode in
                            selectedQRCode = qrCode
                        }
                    )
                }
            }
        }
        .navigationTitle("Manage QR Codes")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await hook.loadCampaigns()
        }
        .sheet(item: $selectedQRCode) { qrCode in
            QRCodeDetailView(qrCode: qrCode)
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

