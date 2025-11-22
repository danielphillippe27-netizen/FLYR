import Foundation
import SwiftUI
import Combine
import CoreLocation

@MainActor
class QRCodeGeneratorViewModel: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var qrCodes: [QRCodeAddress] = []
    @Published var isLoading = false
    @Published var isLoadingCampaigns = false
    @Published var errorMessage: String?
    
    private let campaignsAPI = CampaignsAPI.shared
    
    // MARK: - Campaign Loading (Lightweight - no addresses)
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        defer { isLoadingCampaigns = false }
        
        do {
            // Fetch only campaign metadata (no addresses)
            let dbRows = try await campaignsAPI.fetchCampaignsMetadata()
            campaigns = dbRows.map { CampaignListItem(from: $0) }
            print("✅ [QR] Loaded \(campaigns.count) campaigns (metadata only)")
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [QR] Error loading campaigns: \(error)")
        }
    }
    
    // MARK: - Address Loading (Only when campaign is selected)
    
    func loadAddressesForCampaign(_ campaignId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch addresses for the selected campaign
            let addresses = try await campaignsAPI.fetchAddresses(campaignId: campaignId)
            qrCodes = addresses.map { addressRow in
                let (webURL, deepLinkURL) = QRCodeAddress.generateURLs(for: addressRow.id)
                
                return QRCodeAddress(
                    addressId: addressRow.id,
                    formatted: addressRow.formatted,
                    coordinate: CLLocationCoordinate2D(latitude: addressRow.lat, longitude: addressRow.lon),
                    webURL: webURL,
                    deepLinkURL: deepLinkURL
                )
            }
            
            // Update the address count for the selected campaign
            if let index = campaigns.firstIndex(where: { $0.id == campaignId }) {
                campaigns[index] = CampaignListItem(
                    from: try await campaignsAPI.fetchCampaignDBRow(id: campaignId),
                    addressCount: addresses.count
                )
            }
            
            print("✅ [QR] Generated \(qrCodes.count) QR codes for campaign")
        } catch {
            errorMessage = "Failed to load addresses: \(error.localizedDescription)"
            print("❌ [QR] Error loading addresses: \(error)")
        }
    }
    
    // MARK: - Clear
    
    func clearAddresses() {
        qrCodes = []
    }
    
    // MARK: - Share
    
    func shareAllQRCodes() {
        // TODO: Implement share all functionality
        print("📤 [QR] Share all QR codes")
    }
}

