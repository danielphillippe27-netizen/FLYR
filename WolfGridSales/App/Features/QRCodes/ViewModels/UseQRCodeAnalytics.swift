import Foundation
import SwiftUI
import Combine

/// Hook for QR Code Analytics
/// Handles scan data fetching and aggregation
@MainActor
class UseQRCodeAnalytics: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var selectedAddressId: UUID?
    @Published var addresses: [AddressRow] = []
    @Published var scans: [QRCodeScan] = []
    @Published var summary: QRCodeAnalyticsSummary?
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
        }
    }
    
    func loadAddressesForCampaign(_ campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            addresses = try await api.fetchAddressesForCampaign(campaignId: campaignId)
            selectedCampaignId = campaignId
        } catch {
            errorMessage = "Failed to load addresses: \(error.localizedDescription)"
        }
    }
    
    func loadScansForCampaign(_ campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            scans = try await api.fetchScansForCampaign(campaignId: campaignId)
            let addressCount = addresses.count
            let recentScans = Array(scans.prefix(20))
            
            summary = QRCodeAnalyticsSummary(
                totalScans: scans.count,
                addressCount: addressCount,
                recentScans: recentScans,
                scansByDate: groupScansByDate(scans)
            )
            selectedAddressId = nil // Clear address filter
        } catch {
            errorMessage = "Failed to load scans: \(error.localizedDescription)"
        }
    }
    
    func loadScansForAddress(_ addressId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            scans = try await api.fetchScansForAddress(addressId: addressId)
            summary = QRCodeAnalyticsSummary(
                totalScans: scans.count,
                addressCount: 1,
                recentScans: Array(scans.prefix(20)),
                scansByDate: groupScansByDate(scans)
            )
            selectedAddressId = addressId
        } catch {
            errorMessage = "Failed to load scans: \(error.localizedDescription)"
        }
    }
    
    private func groupScansByDate(_ scans: [QRCodeScan]) -> [Date: Int] {
        let calendar = Calendar.current
        var grouped: [Date: Int] = [:]
        
        for scan in scans {
            let date = calendar.startOfDay(for: scan.scannedAt)
            grouped[date, default: 0] += 1
        }
        
        return grouped
    }
}

