import Foundation
import SwiftUI
import Combine

/// Hook for QR Code management
/// Handles viewing and managing existing QR codes
@MainActor
class UseQRCodeManage: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var qrCodes: [QRCodeAddress] = []
    @Published var isLoading = false
    @Published var isLoadingCampaigns = false
    @Published var errorMessage: String?
    
    private let api = QRCodeAPI.shared
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        errorMessage = nil
        defer { isLoadingCampaigns = false }
        
        do {
            campaigns = try await api.fetchCampaigns(workspaceId: WorkspaceContext.shared.workspaceId)
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [QR Manage] Error: \(error)")
        }
    }
    
    func loadQRCodesForCampaign(_ campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            qrCodes = try await api.fetchQRCodesForCampaign(campaignId: campaignId)
            selectedCampaignId = campaignId
        } catch {
            errorMessage = "Failed to load QR codes: \(error.localizedDescription)"
            print("❌ [QR Manage] Error: \(error)")
        }
    }
}

