import Foundation

/// Service for bulk generating landing pages for all addresses in a campaign
actor BulkLandingPageGenerator {
    static let shared = BulkLandingPageGenerator()
    
    private let generator = LandingPageGenerator.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    private init() {}
    
    /// Generate landing pages for all addresses in a campaign
    /// - Parameters:
    ///   - campaign: Campaign to generate pages for
    ///   - progressCallback: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: Array of generated landing pages
    func generateForAllAddresses(
        campaign: CampaignDBRow,
        progressCallback: ((Double) async -> Void)? = nil
    ) async throws -> [LandingPage] {
        print("🚀 [BulkLandingPageGenerator] Starting bulk generation for campaign \(campaign.id)")
        
        // Fetch all addresses for the campaign
        let addresses = try await campaignsAPI.fetchAddresses(campaignId: campaign.id)
        print("📋 [BulkLandingPageGenerator] Found \(addresses.count) addresses")
        
        guard !addresses.isEmpty else {
            print("⚠️ [BulkLandingPageGenerator] No addresses found for campaign")
            return []
        }
        
        var generatedPages: [LandingPage] = []
        let total = addresses.count
        
        // Process addresses in batches to avoid overwhelming the system
        let batchSize = 10
        for (index, address) in addresses.enumerated() {
            do {
                let page = try await generator.generateLandingPage(
                    campaign: campaign,
                    address: address
                )
                generatedPages.append(page)
                
                // Update progress
                let progress = Double(index + 1) / Double(total)
                if let callback = progressCallback {
                    await callback(progress)
                }
                
                // Log every 10 addresses
                if (index + 1) % 10 == 0 {
                    print("📊 [BulkLandingPageGenerator] Progress: \(index + 1)/\(total) (\(Int(progress * 100))%)")
                }
            } catch {
                print("❌ [BulkLandingPageGenerator] Failed to generate page for address \(address.id): \(error)")
                // Continue with next address even if one fails
            }
            
            // Small delay between batches to avoid rate limiting
            if (index + 1) % batchSize == 0 {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        print("✅ [BulkLandingPageGenerator] Completed: Generated \(generatedPages.count)/\(total) landing pages")
        return generatedPages
    }
    
    /// Generate landing pages for specific addresses
    /// - Parameters:
    ///   - campaign: Campaign model
    ///   - addressIds: Array of address IDs to generate pages for
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Array of generated landing pages
    func generateForAddresses(
        campaign: CampaignDBRow,
        addressIds: [UUID],
        progressCallback: ((Double) async -> Void)? = nil
    ) async throws -> [LandingPage] {
        print("🚀 [BulkLandingPageGenerator] Generating pages for \(addressIds.count) specific addresses")
        
        // Fetch all addresses for the campaign
        let allAddresses = try await campaignsAPI.fetchAddresses(campaignId: campaign.id)
        
        // Filter to only requested addresses
        let addresses = allAddresses.filter { addressIds.contains($0.id) }
        
        guard !addresses.isEmpty else {
            print("⚠️ [BulkLandingPageGenerator] No matching addresses found")
            return []
        }
        
        var generatedPages: [LandingPage] = []
        let total = addresses.count
        
        for (index, address) in addresses.enumerated() {
            do {
                let page = try await generator.generateLandingPage(
                    campaign: campaign,
                    address: address
                )
                generatedPages.append(page)
                
                let progress = Double(index + 1) / Double(total)
                if let callback = progressCallback {
                    await callback(progress)
                }
            } catch {
                print("❌ [BulkLandingPageGenerator] Failed to generate page for address \(address.id): \(error)")
            }
        }
        
        print("✅ [BulkLandingPageGenerator] Completed: Generated \(generatedPages.count)/\(total) landing pages")
        return generatedPages
    }
}

