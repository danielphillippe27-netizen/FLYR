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
    
    private var isFetching = false
    private var lastFetchTime: Date?
    
    func loadCampaignsAndFarms() async {
        guard !isFetching else { return }
        if let last = lastFetchTime, Date().timeIntervalSince(last) < 3 { return }
        isFetching = true
        lastFetchTime = Date()
        isLoading = true
        errorMessage = nil
        defer {
            isFetching = false
            isLoading = false
        }
        
        async let campaignsTask = loadCampaigns()
        async let farmsTask = loadFarms()
        
        _ = await (campaignsTask, farmsTask)
    }
    
    private func loadCampaigns() async {
        do {
            campaigns = try await qrCodeAPI.fetchCampaigns()
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [Map Picker] Error loading campaigns: \(error)")
        }
    }
    
    private func loadFarms() async {
        do {
            let farmRows = try await qrRepository.fetchFarms()
            farms = farmRows.map { $0.toFarmListItem() }
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = "Failed to load farms: \(error.localizedDescription)"
            print("❌ [Map Picker] Error loading farms: \(error)")
        }
    }
}

