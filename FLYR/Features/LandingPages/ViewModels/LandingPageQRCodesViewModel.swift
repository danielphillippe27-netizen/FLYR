import Foundation
import SwiftUI
import Combine

@MainActor
class LandingPageQRCodesViewModel: ObservableObject {
    @Published var linkedQRCodes: [QRCode] = []
    @Published var availableQRCodes: [QRCode] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let qrService = SupabaseQRService.shared
    
    func loadQRCodes(campaignId: UUID, landingPageId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let allQRCodes = try await qrService.fetchQRCodesForCampaign(campaignId: campaignId)
            
            // Split into linked and available
            linkedQRCodes = allQRCodes.filter { $0.landingPageId == landingPageId }
            availableQRCodes = allQRCodes.filter { $0.landingPageId != landingPageId }
        } catch let err {
            self.error = "Failed to load QR codes: \(err.localizedDescription)"
            print("❌ [LandingPageQRCodesViewModel] Error loading QR codes: \(err)")
        }
    }
    
    func linkQR(_ qrCode: QRCode, landingPageId: UUID, variant: String? = nil) async {
        error = nil
        
        do {
            let updated = try await qrService.linkQRCode(qrId: qrCode.id, landingPageId: landingPageId, variant: variant)
            
            // Update local arrays
            if let index = availableQRCodes.firstIndex(where: { $0.id == qrCode.id }) {
                availableQRCodes.remove(at: index)
            }
            linkedQRCodes.append(updated)
        } catch let err {
            self.error = "Failed to link QR code: \(err.localizedDescription)"
            print("❌ [LandingPageQRCodesViewModel] Error linking QR code: \(err)")
        }
    }
    
    func unlinkQR(_ qrCode: QRCode) async {
        error = nil
        
        do {
            let updated = try await qrService.unlinkQRCode(qrId: qrCode.id)
            
            // Update local arrays
            if let index = linkedQRCodes.firstIndex(where: { $0.id == qrCode.id }) {
                linkedQRCodes.remove(at: index)
            }
            availableQRCodes.append(updated)
        } catch let err {
            self.error = "Failed to unlink QR code: \(err.localizedDescription)"
            print("❌ [LandingPageQRCodesViewModel] Error unlinking QR code: \(err)")
        }
    }
}


