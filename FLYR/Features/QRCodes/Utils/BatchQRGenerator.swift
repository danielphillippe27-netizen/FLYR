import Foundation
import Supabase
import UIKit

/// Generator for creating QR codes for a batch
public struct BatchQRGenerator {
    /// Generate QR codes for all addresses in a campaign based on batch configuration
    /// - Parameters:
    ///   - batch: The batch configuration
    ///   - campaignId: Campaign ID to fetch addresses from
    ///   - userDefaultWebsite: User's default website URL (optional)
    /// - Returns: Array of created QR codes
    public static func generateBatchQRCodes(
        _ batch: Batch,
        campaignId: UUID,
        userDefaultWebsite: String? = nil
    ) async throws -> [QRCode] {
        // Fetch addresses from campaign
        let campaignsAPI = CampaignsAPI.shared
        let addresses = try await campaignsAPI.fetchAddresses(campaignId: campaignId)
        
        guard !addresses.isEmpty else {
            throw BatchQRGeneratorError.noAddresses("No addresses found for campaign")
        }
        
        print("✅ [Batch QR Generator] Found \(addresses.count) addresses for campaign")
        
        // Resolve base URL for the batch
        let baseURL = BatchURLResolver.resolveBatchURL(
            batch,
            userDefaultWebsite: userDefaultWebsite
        )
        
        // Generate QR codes for each address
        let qrRepository = QRRepository.shared
        var createdQRCodes: [QRCode] = []
        
        // Use TaskGroup for parallel processing
        try await withThrowingTaskGroup(of: QRCode?.self) { group in
            for address in addresses {
                group.addTask {
                    do {
                        // Resolve URL with address ID appended
                        let qrUrl = BatchURLResolver.resolveBatchURL(
                            batch,
                            userDefaultWebsite: userDefaultWebsite,
                            addressId: address.id
                        )
                        
                        // Generate QR code image
                        guard let base64Image = QRCodeGenerator.generateBase64(from: qrUrl) else {
                            print("⚠️ [Batch QR Generator] Failed to generate QR code for address \(address.id)")
                            return nil
                        }
                        
                        // Prepare metadata
                        var metadataDict: [String: AnyCodable] = [:]
                        metadataDict["entity_name"] = AnyCodable(address.formatted)
                        metadataDict["device_info"] = AnyCodable(UIDevice.current.model)
                        metadataDict["batch_name"] = AnyCodable(batch.name)
                        
                        // Insert into database with batch_id
                        var qrCodeData: [String: AnyCodable] = [
                            "address_id": AnyCodable(address.id.uuidString),
                            "campaign_id": AnyCodable(campaignId.uuidString),
                            "batch_id": AnyCodable(batch.id.uuidString),
                            "qr_url": AnyCodable(qrUrl),
                            "qr_image": AnyCodable(base64Image),
                            "metadata": AnyCodable(metadataDict)
                        ]
                        
                        let client = SupabaseManager.shared.client
                        let response = try await client
                            .from("qr_codes")
                            .insert(qrCodeData)
                            .select()
                            .execute()
                        
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
                        
                        guard let dbRow = dbRows.first else {
                            print("⚠️ [Batch QR Generator] No data returned for address \(address.id)")
                            return nil
                        }
                        
                        return dbRow.toQRCode()
                    } catch {
                        print("⚠️ [Batch QR Generator] Failed to create QR code for address \(address.id): \(error)")
                        return nil
                    }
                }
            }
            
            // Collect results
            for try await qrCode in group {
                if let qrCode = qrCode {
                    createdQRCodes.append(qrCode)
                }
            }
        }
        
        print("✅ [Batch QR Generator] Created \(createdQRCodes.count) QR codes for batch \(batch.id)")
        return createdQRCodes
    }
}

// MARK: - Errors

enum BatchQRGeneratorError: LocalizedError {
    case noAddresses(String)
    
    var errorDescription: String? {
        switch self {
        case .noAddresses(let message):
            return message
        }
    }
}

