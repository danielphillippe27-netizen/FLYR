import Foundation
import SwiftUI
import Combine

@MainActor
class MapCampaignPickerViewModel: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var farms: [FarmListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let qrCodeAPI = QRCodeAPI.shared
    private let qrRepository = QRRepository.shared
    
    func loadCampaignsAndFarms() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        async let campaignsTask = loadCampaigns()
        async let farmsTask = loadFarms()
        
        _ = await (campaignsTask, farmsTask)
    }
    
    private func loadCampaigns() async {
        do {
            campaigns = try await qrCodeAPI.fetchCampaigns()
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [Map Picker] Error loading campaigns: \(error)")
        }
    }
    
    private func loadFarms() async {
        do {
            let farmRows = try await qrRepository.fetchFarms()
            farms = farmRows.map { $0.toFarmListItem() }
        } catch {
            errorMessage = "Failed to load farms: \(error.localizedDescription)"
            print("❌ [Map Picker] Error loading farms: \(error)")
        }
    }
}

