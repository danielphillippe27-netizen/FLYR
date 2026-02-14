import Foundation
import Combine

@MainActor
final class CampaignsHooks: ObservableObject {
    @Published var campaigns: [Campaign] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadCampaigns(forUserId userId: UUID? = nil) async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let userId = userId {
                campaigns = try await CampaignsAPI.shared.fetchCampaignsForUser(userId: userId)
            } else {
                campaigns = try await CampaignsAPI.shared.fetchCampaigns()
            }
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
    
    func createCampaign(title: String, description: String, region: String?) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await CampaignsAPI.shared.createCampaign(title: title, description: description, region: region)
            // Refresh the list after successful creation
            await loadCampaigns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
