import Foundation

/// Helper for integrating Farm workflow with other systems (QR, Campaigns, CRM, Stats)
enum FarmIntegrationHelper {
    // MARK: - QR Code Integration
    
    /// Link a QR scan to a farm touch
    /// This should be called when a QR code is scanned that's associated with a farm touch
    static func linkQRScanToTouch(
        touchId: UUID,
        scanData: QRScanData
    ) async throws {
        // TODO: Integrate with QR scan tracking system
        // 1. Find the QR code that was scanned
        // 2. Check if it's linked to a campaign or batch that's attached to the touch
        // 3. Create a farm_lead record with lead_source = "qr_scan"
        // 4. Link the lead to the touch
        
        let leadService = FarmLeadService.shared
        
        // Example implementation:
        // let lead = FarmLead(
        //     farmId: farmId,
        //     touchId: touchId,
        //     leadSource: .qrScan,
        //     name: scanData.name,
        //     phone: scanData.phone,
        //     email: scanData.email,
        //     address: scanData.address
        // )
        // try await leadService.addLead(lead)
    }
    
    // MARK: - Campaign Integration
    
    /// Attach a campaign to a farm touch
    /// This allows tracking campaign performance within the farm context
    static func attachCampaignToTouch(
        touchId: UUID,
        campaignId: UUID
    ) async throws {
        // This is handled by FarmTouchService.attachCampaign
        // Additional integration: Pull campaign metrics into phase results
    }
    
    // MARK: - Contacts/CRM Integration
    
    /// Link a farm lead to a contact in the CRM
    static func linkLeadToContact(
        leadId: UUID,
        contactId: UUID
    ) async throws {
        // TODO: Integrate with ContactsService
        // 1. Find the farm lead
        // 2. Create or update contact with farm lead information
        // 3. Link contact to farm via farm_id field
    }
    
    // MARK: - Stats Integration
    
    /// Update stats with farm metrics
    static func updateStatsWithFarmMetrics(
        farmId: UUID,
        touches: [FarmTouch],
        leads: [FarmLead]
    ) async throws {
        // TODO: Integrate with StatsService
        // 1. Calculate farm-specific metrics
        // 2. Update user stats with farm contributions
        // 3. Include in leaderboard calculations
    }
}

// MARK: - QR Scan Data

struct QRScanData {
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let timestamp: Date
}



