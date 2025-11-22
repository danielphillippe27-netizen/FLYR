import SwiftUI
import Combine
import CoreLocation

/// Print QR Code view - allows selecting campaigns and printing QR codes
struct QRCodePrintView: View {
    @StateObject private var hook = UseQRCodePrint()
    @State private var selectedCampaignId: UUID?
    @State private var showExportModal = false
    
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
                        selectedId: selectedCampaignId,
                        onSelect: { campaignId in
                            selectedCampaignId = campaignId
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
                        illustration: "printer",
                        title: "No QR Codes",
                        message: selectedCampaignId == nil 
                            ? "Select a campaign to print QR codes"
                            : "No QR codes found for this campaign"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 160), spacing: 20)
                        ], spacing: 20) {
                            ForEach(hook.qrCodes) { qrCode in
                                QRCard(
                                    qr: qrCode,
                                    onPrint: {
                                        printQRCode(qrCode)
                                    }
                                )
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
        .navigationTitle("Print QR Codes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedCampaignId != nil && !hook.qrCodes.isEmpty {
                    Button("Export All") {
                        showExportModal = true
                    }
                }
            }
        }
        .task {
            await hook.loadCampaigns()
        }
        .sheet(isPresented: $showExportModal) {
            if let campaignId = selectedCampaignId {
                ExportModalView(
                    campaignId: campaignId,
                    batchName: "QR Codes Export",
                    addresses: hook.qrCodes,
                    onDismiss: {}
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func printQRCode(_ qrCode: QRCodeAddress) {
        // TODO: Implement print functionality
        print("Print QR code: \(qrCode.id)")
    }
}

/// View model for QR code print view
@MainActor
final class UseQRCodePrint: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var qrCodes: [QRCodeAddress] = []
    @Published var isLoadingCampaigns = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let api = QRCodeAPI.shared
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        errorMessage = nil
        defer { isLoadingCampaigns = false }
        
        do {
            campaigns = try await api.fetchCampaigns()
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [QR Print] Error loading campaigns: \(error)")
        }
    }
    
    func loadQRCodesForCampaign(_ campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            qrCodes = try await api.fetchQRCodesForCampaign(campaignId: campaignId)
        } catch {
            errorMessage = "Failed to load QR codes: \(error.localizedDescription)"
            print("❌ [QR Print] Error loading QR codes: \(error)")
        }
    }
}


