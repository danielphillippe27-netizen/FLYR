import Foundation
import Supabase
import UIKit

/// Repository for QR code operations with Supabase
actor QRRepository {
    static let shared = QRRepository()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Create QR Code
    
    /// Create a QR code for a specific address
    /// - Parameters:
    ///   - addressId: Address ID from campaign_addresses
    ///   - addressFormatted: Formatted address string (for metadata)
    ///   - campaignId: Optional campaign ID for reference
    ///   - batchName: Optional batch name for grouping QR codes
    /// - Returns: The created or existing QR code
    func createQRCodeForAddress(
        addressId: UUID,
        addressFormatted: String,
        campaignId: UUID? = nil,
        batchName: String? = nil
    ) async throws -> QRCode {
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        let qrUrl: String
        if let campaignId = campaignId {
            qrUrl = "https://flyrpro.app/address/\(addressId.uuidString)?device=\(deviceUUID)&campaign=\(campaignId.uuidString)"
        } else {
            qrUrl = "https://flyrpro.app/address/\(addressId.uuidString)?device=\(deviceUUID)"
        }
        
        // Check for existing QR code for this address
        if let existing = try await findExistingQRCodeForAddress(addressId: addressId) {
            print("✅ [QR Repository] Found existing QR code for address \(addressId)")
            return existing
        }
        
        // Generate QR code image
        guard let base64Image = QRCodeGenerator.generateBase64(from: qrUrl) else {
            throw QRRepositoryError.generationFailed("Failed to generate QR code image")
        }
        
        // Prepare metadata
        var metadataDict: [String: AnyCodable] = [:]
        metadataDict["entity_name"] = AnyCodable(addressFormatted)
        metadataDict["device_info"] = AnyCodable(UIDevice.current.model)
        if let batchName = batchName {
            metadataDict["batch_name"] = AnyCodable(batchName)
        }
        
        // Insert into database
        var qrCodeData: [String: AnyCodable] = [
            "address_id": AnyCodable(addressId.uuidString),
            "qr_url": AnyCodable(qrUrl),
            "qr_image": AnyCodable(base64Image),
            "metadata": AnyCodable(metadataDict)
        ]
        
        // Optionally include campaign_id for reference (in metadata, not as FK)
        if let campaignId = campaignId {
            metadataDict["campaign_id"] = AnyCodable(campaignId.uuidString)
            qrCodeData["metadata"] = AnyCodable(metadataDict)
        }
        
        print("🔷 [QR Repository] Creating QR code for address \(addressId)")
        
        let response = try await client
            .from("qr_codes")
            .insert(qrCodeData)
            .select()
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first else {
            throw QRRepositoryError.insertFailed("No data returned from insert")
        }
        
        print("✅ [QR Repository] QR code created with ID: \(dbRow.id)")
        return dbRow.toQRCode()
    }
    
    /// Create QR codes for all addresses in a campaign (parallel processing for speed)
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - addresses: Array of address rows with id and formatted address
    ///   - batchName: Optional batch name for grouping QR codes
    /// - Returns: Array of created QR codes
    func createQRCodesForCampaignAddresses(
        campaignId: UUID,
        addresses: [(id: UUID, formatted: String)],
        batchName: String? = nil
    ) async throws -> [QRCode] {
        // Use TaskGroup for parallel processing to speed up creation
        return try await withThrowingTaskGroup(of: QRCode?.self) { group in
            var createdQRCodes: [QRCode] = []
            
            // Launch all tasks in parallel
            for address in addresses {
                group.addTask {
                    do {
                        return try await self.createQRCodeForAddress(
                            addressId: address.id,
                            addressFormatted: address.formatted,
                            campaignId: campaignId,
                            batchName: batchName
                        )
                    } catch {
                        print("⚠️ [QR Repository] Failed to create QR code for address \(address.id): \(error)")
                        return nil
                    }
                }
            }
            
            // Collect results as they complete
            for try await qrCode in group {
                if let qrCode = qrCode {
                    createdQRCodes.append(qrCode)
                }
            }
            
            print("✅ [QR Repository] Created \(createdQRCodes.count) QR codes for campaign \(campaignId)")
            return createdQRCodes
        }
    }
    
    /// Create a QR code for a campaign or farm with duplicate prevention
    /// - Parameters:
    ///   - campaignId: Campaign ID (if creating for campaign)
    ///   - farmId: Farm ID (if creating for farm)
    ///   - entityName: Name of the entity (for metadata)
    ///   - addressCount: Number of addresses (for metadata)
    /// - Returns: The created or existing QR code
    func createQRCode(
        campaignId: UUID? = nil,
        farmId: UUID? = nil,
        entityName: String? = nil,
        addressCount: Int? = nil
    ) async throws -> QRCode {
        // Validate that exactly one entity ID is provided
        guard (campaignId != nil) != (farmId != nil) else {
            throw QRRepositoryError.invalidEntity("Either campaignId or farmId must be provided, but not both")
        }
        
        let entityId = campaignId ?? farmId!
        let entityType = campaignId != nil ? "campaign" : "farm"
        
        // Generate QR URL with device UUID for analytics
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let qrUUID = UUID().uuidString
        let qrUrl: String
        if let campaignId = campaignId {
            qrUrl = "https://flyrpro.app/qr/\(campaignId.uuidString)/\(qrUUID)?device=\(deviceUUID)"
        } else {
            qrUrl = "https://flyrpro.app/qr/farm/\(farmId!.uuidString)/\(qrUUID)?device=\(deviceUUID)"
        }
        
        // Check for duplicate first
        if let existing = try await findExistingQRCode(campaignId: campaignId, farmId: farmId, qrUrl: qrUrl) {
            print("✅ [QR Repository] Found existing QR code for \(entityType) \(entityId)")
            return existing
        }
        
        // Generate QR code image
        guard let base64Image = QRCodeGenerator.generateBase64(from: qrUrl) else {
            throw QRRepositoryError.generationFailed("Failed to generate QR code image")
        }
        
        // Prepare metadata - build dictionary with unwrapped optionals as AnyCodable
        var metadataDict: [String: AnyCodable] = [:]
        if let addressCount = addressCount {
            metadataDict["address_count"] = AnyCodable(addressCount)
        }
        if let entityName = entityName {
            metadataDict["entity_name"] = AnyCodable(entityName)
        }
        metadataDict["device_info"] = AnyCodable(UIDevice.current.model)
        
        // Insert into database
        // Wrap metadata dictionary in AnyCodable (Supabase client handles nested structures for JSONB)
        var qrCodeData: [String: AnyCodable] = [
            "qr_url": AnyCodable(qrUrl),
            "qr_image": AnyCodable(base64Image),
            "metadata": AnyCodable(metadataDict)
        ]
        
        // Only include campaign_id or farm_id if they're not nil
        if let campaignId = campaignId {
            qrCodeData["campaign_id"] = AnyCodable(campaignId.uuidString)
        }
        if let farmId = farmId {
            qrCodeData["farm_id"] = AnyCodable(farmId.uuidString)
        }
        
        print("🔷 [QR Repository] Creating QR code for \(entityType) \(entityId)")
        
        let response = try await client
            .from("qr_codes")
            .insert(qrCodeData)
            .select()
            .execute()
        
        // Decode with proper date handling
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first else {
            throw QRRepositoryError.insertFailed("No data returned from insert")
        }
        
        print("✅ [QR Repository] QR code created with ID: \(dbRow.id)")
        return dbRow.toQRCode()
    }
    
    /// Create a new QR code with explicit URL and image (for Create QR flow)
    func createQRCodeWithSlug(
        campaignId: UUID? = nil,
        farmId: UUID? = nil,
        landingPageId: UUID? = nil,
        slug: String? = nil,
        qrUrl: String,
        qrImage: String,
        variant: String? = nil,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> QRCode {
        var insertData: [String: AnyCodable] = [
            "qr_url": AnyCodable(qrUrl),
            "qr_image": AnyCodable(qrImage)
        ]
        
        if let campaignId = campaignId {
            insertData["campaign_id"] = AnyCodable(campaignId.uuidString)
        }
        
        if let farmId = farmId {
            insertData["farm_id"] = AnyCodable(farmId.uuidString)
        }
        
        if let landingPageId = landingPageId {
            insertData["landing_page_id"] = AnyCodable(landingPageId.uuidString)
        }
        
        if let slug = slug, !slug.isEmpty {
            insertData["slug"] = AnyCodable(slug)
        }
        
        if let variant = variant, !variant.isEmpty {
            insertData["qr_variant"] = AnyCodable(variant)
        }
        
        if let metadata = metadata, !metadata.isEmpty {
            insertData["metadata"] = AnyCodable(metadata)
        }
        
        let response = try await client
            .from("qr_codes")
            .insert(insertData)
            .select()
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first else {
            throw QRRepositoryError.insertFailed("No data returned from insert")
        }
        
        return dbRow.toQRCode()
    }
    
    // MARK: - Fetch QR Codes
    
    /// Find existing QR code for an address
    private func findExistingQRCodeForAddress(addressId: UUID) async throws -> QRCode? {
        let response = try await client
            .from("qr_codes")
            .select()
            .eq("address_id", value: addressId.uuidString)
            .limit(1)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.first?.toQRCode()
    }
    
    /// Find existing QR code to prevent duplicates
    private func findExistingQRCode(
        campaignId: UUID?,
        farmId: UUID?,
        qrUrl: String
    ) async throws -> QRCode? {
        var query = client.from("qr_codes").select()
        
        if let campaignId = campaignId {
            query = query.eq("campaign_id", value: campaignId.uuidString)
        } else if let farmId = farmId {
            query = query.eq("farm_id", value: farmId.uuidString)
        }
        
        query = query.eq("qr_url", value: qrUrl)
        
        let response = try await query
            .limit(1)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.first?.toQRCode()
    }
    
    /// Fetch QR codes for a campaign (address-based QR codes)
    /// Fetches QR codes where address_id matches addresses in the campaign
    func fetchQRCodesForCampaign(_ campaignId: UUID) async throws -> [QRCode] {
        // Get all address IDs for this campaign first
        let addressResponse = try await client
            .from("campaign_addresses")
            .select("id")
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        
        struct AddressIdRow: Codable {
            let id: UUID
        }
        
        let decoder = createSupabaseDecoder()
        let addressRows: [AddressIdRow] = try decoder.decode([AddressIdRow].self, from: addressResponse.data)
        let addressIds = addressRows.map { $0.id.uuidString }
        
        guard !addressIds.isEmpty else {
            return []
        }
        
        // Fetch QR codes for these addresses
        let response = try await client
            .from("qr_codes")
            .select()
            .in("address_id", values: addressIds)
            .order("created_at", ascending: false)
            .execute()
        
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.map { $0.toQRCode() }
    }
    
    /// Fetch QR code for a specific address
    func fetchQRCodeForAddress(_ addressId: UUID) async throws -> QRCode? {
        let response = try await client
            .from("qr_codes")
            .select()
            .eq("address_id", value: addressId.uuidString)
            .limit(1)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.first?.toQRCode()
    }
    
    /// Fetch QR codes for a farm
    func fetchQRCodesForFarm(_ farmId: UUID) async throws -> [QRCode] {
        let response = try await client
            .from("qr_codes")
            .select()
            .eq("farm_id", value: farmId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.map { $0.toQRCode() }
    }
    
    /// Fetch QR codes for a batch
    func fetchQRCodesForBatch(batchId: UUID) async throws -> [QRCode] {
        let response = try await client
            .from("qr_codes")
            .select()
            .eq("batch_id", value: batchId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.map { $0.toQRCode() }
    }
    
    /// Fetch a single QR code by ID
    func fetchQRCode(id: UUID) async throws -> QRCode? {
        let response = try await client
            .from("qr_codes")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.first?.toQRCode()
    }
    
    // MARK: - Update QR Code
    
    /// Update QR code metadata (name and printed status)
    func updateQRCode(id: UUID, name: String?, isPrinted: Bool?) async throws -> QRCode {
        // First fetch the current QR code to get existing metadata
        guard let currentQR = try await fetchQRCode(id: id) else {
            throw QRRepositoryError.notFound
        }
        
        // Build updated metadata dictionary, preserving existing values
        var metadataDict: [String: AnyCodable] = [:]
        
        // Preserve existing metadata
        if let existingMetadata = currentQR.metadata {
            if let addressCount = existingMetadata.addressCount {
                metadataDict["address_count"] = AnyCodable(addressCount)
            }
            if let entityName = existingMetadata.entityName {
                metadataDict["entity_name"] = AnyCodable(entityName)
            }
            if let deviceInfo = existingMetadata.deviceInfo {
                metadataDict["device_info"] = AnyCodable(deviceInfo)
            }
            if let batchName = existingMetadata.batchName {
                metadataDict["batch_name"] = AnyCodable(batchName)
            }
            // Preserve existing name and isPrinted if not being updated
            if name == nil, let existingName = existingMetadata.name {
                metadataDict["name"] = AnyCodable(existingName)
            }
            if isPrinted == nil, let existingIsPrinted = existingMetadata.isPrinted {
                metadataDict["is_printed"] = AnyCodable(existingIsPrinted)
            }
        }
        
        // Update name and isPrinted if provided
        if let name = name {
            metadataDict["name"] = AnyCodable(name)
        }
        
        if let isPrinted = isPrinted {
            metadataDict["is_printed"] = AnyCodable(isPrinted)
        }
        
        // Update in database using JSONB merge
        let updateData: [String: AnyCodable] = [
            "metadata": AnyCodable(metadataDict)
        ]
        
        let response = try await client
            .from("qr_codes")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first else {
            throw QRRepositoryError.insertFailed("No data returned from update")
        }
        
        print("✅ [QR Repository] QR code updated with ID: \(dbRow.id)")
        return dbRow.toQRCode()
    }
    
    /// Update QR code preview image (for batch PDF previews)
    func updateQRCodePreview(id: UUID, previewImage: String) async throws -> QRCode {
        let updateData: [String: AnyCodable] = [
            "qr_image": AnyCodable(previewImage)
        ]
        
        let response = try await client
            .from("qr_codes")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first else {
            throw QRRepositoryError.insertFailed("No data returned from update")
        }
        
        print("✅ [QR Repository] QR code preview updated with ID: \(dbRow.id)")
        return dbRow.toQRCode()
    }
    
    // MARK: - Farms
    
    /// Fetch all farms for the current user
    func fetchFarms() async throws -> [QRFarmDBRow] {
        // Get current user ID
        let session = try await client.auth.session
        let userId = session.user.id
        
        let response = try await client
            .from("farms")
            .select()
            .eq("owner_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = createSupabaseDecoder()
        return try decoder.decode([QRFarmDBRow].self, from: response.data)
    }
    
    // MARK: - Helper
    
    /// Create a JSONDecoder with Supabase date handling (nonisolated)
    private nonisolated func createSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let dt = iso.date(from: s) { return dt }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let dt = iso2.date(from: s) { return dt }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
        }
        return decoder
    }
}

// MARK: - Errors

enum QRRepositoryError: Error, LocalizedError {
    case invalidEntity(String)
    case generationFailed(String)
    case insertFailed(String)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .invalidEntity(let message):
            return "Invalid entity: \(message)"
        case .generationFailed(let message):
            return "QR code generation failed: \(message)"
        case .insertFailed(let message):
            return "Insert failed: \(message)"
        case .notFound:
            return "QR code not found"
        }
    }
}

