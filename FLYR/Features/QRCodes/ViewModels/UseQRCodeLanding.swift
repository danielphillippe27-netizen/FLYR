import Foundation
import SwiftUI
import Combine

/// Hook for Landing Page management
/// Handles address content CRUD operations
@MainActor
class UseQRCodeLanding: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var addresses: [AddressRow] = []
    @Published var selectedAddressId: UUID?
    @Published var addressContent: AddressContent?
    @Published var isLoading = false
    @Published var isLoadingCampaigns = false
    @Published var isSaving = false
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
    
    func loadContentForAddress(_ addressId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            addressContent = try await api.fetchAddressContent(addressId: addressId)
            if addressContent == nil {
                // Create default content if none exists
                addressContent = AddressContent(
                    addressId: addressId,
                    title: "",
                    videos: [],
                    images: [],
                    forms: []
                )
            }
            selectedAddressId = addressId
        } catch {
            errorMessage = "Failed to load content: \(error.localizedDescription)"
        }
    }
    
    func saveContent(_ content: AddressContent) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            addressContent = try await api.upsertAddressContent(content)
        } catch {
            errorMessage = "Failed to save content: \(error.localizedDescription)"
        }
    }
}

