import Foundation
import Supabase

/// Handles uploading export files to Supabase Storage and saving metadata
actor SupabaseUploadService {
    static let shared = SupabaseUploadService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private let bucketName = "qr-exports"
    
    private init() {}
    
    /// Upload export files to Supabase Storage and save metadata
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - batchName: Batch name
    ///   - exportResult: Result containing all generated file URLs
    /// - Returns: Updated ExportResult with Supabase URLs
    /// - Throws: ExportError if upload fails
    func uploadExport(
        campaignId: UUID,
        batchName: String,
        exportResult: ExportResult
    ) async throws -> ExportResult {
        // Ensure bucket exists (create if needed)
        try await ensureBucketExists()
        
        var zipURL: String?
        var pdfGridURL: String?
        var pdfSingleURL: String?
        var csvURL: String?
        
        // Upload ZIP file if present
        if let zipFileURL = exportResult.zipURL {
            zipURL = try await uploadFile(
                fileURL: zipFileURL,
                path: "\(campaignId.uuidString)/\(StringSlugifier.slugify(batchName))_batch.zip"
            )
        }
        
        // Upload PDF Grid if present
        if let pdfGridFileURL = exportResult.pdfGridURL {
            pdfGridURL = try await uploadFile(
                fileURL: pdfGridFileURL,
                path: "\(campaignId.uuidString)/\(StringSlugifier.slugify(batchName))_grid.pdf"
            )
        }
        
        // Upload PDF Single if present
        if let pdfSingleFileURL = exportResult.pdfSingleURL {
            pdfSingleURL = try await uploadFile(
                fileURL: pdfSingleFileURL,
                path: "\(campaignId.uuidString)/\(StringSlugifier.slugify(batchName))_single.pdf"
            )
        }
        
        // Upload CSV if present
        if let csvFileURL = exportResult.csvURL {
            csvURL = try await uploadFile(
                fileURL: csvFileURL,
                path: "\(campaignId.uuidString)/\(StringSlugifier.slugify(batchName))_batch.csv"
            )
        }
        
        // Save metadata to campaign_qr_batches table
        try await saveBatchMetadata(
            campaignId: campaignId,
            batchName: batchName,
            zipURL: zipURL,
            pdfGridURL: pdfGridURL,
            pdfSingleURL: pdfSingleURL,
            csvURL: csvURL
        )
        
        // Return updated result with Supabase URLs
        return ExportResult(
            pdfGridURL: pdfGridURL != nil ? URL(string: pdfGridURL!) : nil,
            pdfSingleURL: pdfSingleURL != nil ? URL(string: pdfSingleURL!) : nil,
            zipURL: zipURL != nil ? URL(string: zipURL!) : nil,
            pngDirectoryURL: exportResult.pngDirectoryURL, // Keep local URL for PNG directory
            csvURL: csvURL != nil ? URL(string: csvURL!) : nil,
            batchName: batchName,
            campaignId: campaignId,
            addressCount: exportResult.addressCount
        )
    }
    
    /// Ensure the storage bucket exists, create if needed
    private func ensureBucketExists() async throws {
        do {
            // Try to get bucket info (will throw if doesn't exist)
            _ = try await client.storage.from(bucketName).list()
        } catch {
            // Bucket doesn't exist, try to create it
            // Note: Bucket creation typically requires admin privileges
            // In production, buckets should be created via Supabase dashboard
            print("⚠️ [Supabase Upload] Bucket '\(bucketName)' may not exist. Please create it in Supabase dashboard.")
            // For now, we'll continue - the upload will fail if bucket doesn't exist
        }
    }
    
    /// Upload a file to Supabase Storage
    /// - Parameters:
    ///   - fileURL: Local file URL to upload
    ///   - path: Storage path (relative to bucket)
    /// - Returns: Public URL or signed URL
    /// - Throws: ExportError if upload fails
    private func uploadFile(fileURL: URL, path: String) async throws -> String {
        // Read file data
        let fileData = try Data(contentsOf: fileURL)
        
        // Upload to Supabase Storage
        do {
            _ = try await client.storage
                .from(bucketName)
                .upload(path: path, file: fileData, options: FileOptions(upsert: true))
            
            // Get public URL (or create signed URL if bucket is private)
            // For public buckets, construct URL directly
            let publicURL = try client.storage
                .from(bucketName)
                .getPublicURL(path: path)
            
            return publicURL.absoluteString
        } catch {
            throw ExportError.supabaseUploadFailed("Failed to upload \(path): \(error.localizedDescription)")
        }
    }
    
    /// Save batch metadata to campaign_qr_batches table
    private func saveBatchMetadata(
        campaignId: UUID,
        batchName: String,
        zipURL: String?,
        pdfGridURL: String?,
        pdfSingleURL: String?,
        csvURL: String?
    ) async throws {
        var batchData: [String: AnyCodable] = [
            "campaign_id": AnyCodable(campaignId.uuidString),
            "batch_name": AnyCodable(batchName)
        ]
        
        if let zipURL = zipURL {
            batchData["zip_url"] = AnyCodable(zipURL)
        }
        if let pdfGridURL = pdfGridURL {
            batchData["pdf_grid_url"] = AnyCodable(pdfGridURL)
        }
        if let pdfSingleURL = pdfSingleURL {
            batchData["pdf_single_url"] = AnyCodable(pdfSingleURL)
        }
        if let csvURL = csvURL {
            batchData["csv_url"] = AnyCodable(csvURL)
        }
        
        do {
            // Use upsert to handle duplicate batch names
            _ = try await client
                .from("campaign_qr_batches")
                .upsert(batchData, onConflict: "campaign_id,batch_name")
                .execute()
            
            print("✅ [Supabase Upload] Saved batch metadata for: \(batchName)")
        } catch {
            throw ExportError.supabaseUploadFailed("Failed to save batch metadata: \(error.localizedDescription)")
        }
    }
    
    /// Get signed URL for a file (24hr expiry)
    /// - Parameters:
    ///   - path: Storage path
    ///   - expiresIn: Expiry time in seconds (default: 86400 = 24 hours)
    /// - Returns: Signed URL
    /// - Throws: ExportError if URL generation fails
    func getSignedURL(path: String, expiresIn: Int = 86400) async throws -> String {
        do {
            let signedURL = try await client.storage
                .from(bucketName)
                .createSignedURL(path: path, expiresIn: expiresIn)
            
            return signedURL.absoluteString
        } catch {
            throw ExportError.supabaseUploadFailed("Failed to create signed URL: \(error.localizedDescription)")
        }
    }
}

