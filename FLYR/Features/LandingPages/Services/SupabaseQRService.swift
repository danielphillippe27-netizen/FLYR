import Foundation
import Supabase

actor SupabaseQRService {
    static let shared = SupabaseQRService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch QR Codes for Campaign
    
    func fetchQRCodesForCampaign(campaignId: UUID) async throws -> [QRCode] {
        let response = try await client
            .from("qr_codes")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRows: [QRCodeDBRow] = try decoder.decode([QRCodeDBRow].self, from: response.data)
        
        return dbRows.map { $0.toQRCode() }
    }
    
    // MARK: - Link QR Code to Landing Page
    
    func linkQRCode(qrId: UUID, landingPageId: UUID, variant: String? = nil, slug: String? = nil) async throws -> QRCode {
        var updateData: [String: AnyCodable] = [
            "landing_page_id": AnyCodable(landingPageId.uuidString)
        ]
        
        if let variant = variant, !variant.isEmpty {
            updateData["qr_variant"] = AnyCodable(variant)
        }
        
        if let slug = slug, !slug.isEmpty {
            updateData["slug"] = AnyCodable(slug)
        }
        
        let response = try await client
            .from("qr_codes")
            .update(updateData)
            .eq("id", value: qrId.uuidString)
            .select()
            .single()
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRow: QRCodeDBRow = try decoder.decode(QRCodeDBRow.self, from: response.data)
        
        return dbRow.toQRCode()
    }
    
    // MARK: - Create QR Code with Slug
    
    /// Create a new QR code with optional slug, landing page, campaign, and farm
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
            .single()
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRow: QRCodeDBRow = try decoder.decode(QRCodeDBRow.self, from: response.data)
        
        return dbRow.toQRCode()
    }
    
    // MARK: - Unlink QR Code from Landing Page
    
    func unlinkQRCode(qrId: UUID) async throws -> QRCode {
        let updateData: [String: AnyCodable] = [
            "landing_page_id": AnyCodable(Optional<UUID>.none),
            "qr_variant": AnyCodable(Optional<String>.none)
        ]
        
        let response = try await client
            .from("qr_codes")
            .update(updateData)
            .eq("id", value: qrId.uuidString)
            .select()
            .single()
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRow: QRCodeDBRow = try decoder.decode(QRCodeDBRow.self, from: response.data)
        
        return dbRow.toQRCode()
    }
    
    // MARK: - Update QR Variant
    
    func updateQRVariant(qrId: UUID, variant: String?) async throws -> QRCode {
        let updateData: [String: AnyCodable] = [
            "qr_variant": AnyCodable(variant)
        ]
        
        let response = try await client
            .from("qr_codes")
            .update(updateData)
            .eq("id", value: qrId.uuidString)
            .select()
            .single()
            .execute()
        
        let decoder = await MainActor.run { JSONDecoder.supabaseDates }
        let dbRow: QRCodeDBRow = try decoder.decode(QRCodeDBRow.self, from: response.data)
        
        return dbRow.toQRCode()
    }
}


