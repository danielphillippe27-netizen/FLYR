import Foundation
import Supabase

/// Repository for batch operations with Supabase
actor BatchRepository {
    static let shared = BatchRepository()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Create Batch
    
    /// Create a new batch
    /// - Parameter batch: Batch model to create
    /// - Returns: The created batch
    func createBatch(_ batch: Batch) async throws -> Batch {
        let session = try await client.auth.session
        let userId = session.user.id
        
        var batchData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "name": AnyCodable(batch.name),
            "qr_type": AnyCodable(batch.qrType.rawValue),
            "export_format": AnyCodable(batch.exportFormat.rawValue)
        ]
        
        if let customURL = batch.customURL {
            batchData["custom_url"] = AnyCodable(customURL)
        }
        
        let response = try await client
            .from("batches")
            .insert(batchData)
            .select()
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [BatchDBRow] = try decoder.decode([BatchDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first,
              let createdBatch = dbRow.toBatch() else {
            throw BatchRepositoryError.insertFailed("No data returned from insert or invalid data")
        }
        
        print("✅ [Batch Repository] Batch created with ID: \(createdBatch.id)")
        return createdBatch
    }
    
    // MARK: - Fetch Batches
    
    /// Fetch all batches for the current user
    /// - Returns: Array of batches
    func fetchBatches() async throws -> [Batch] {
        let session = try await client.auth.session
        let userId = session.user.id
        
        let response: PostgrestResponse<[BatchDBRow]> = try await client
            .from("batches")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        return response.value.compactMap { $0.toBatch() }
    }
    
    /// Fetch a single batch by ID
    /// - Parameter id: Batch ID
    /// - Returns: The batch if found
    func fetchBatch(id: UUID) async throws -> Batch? {
        let response: PostgrestResponse<[BatchDBRow]> = try await client
            .from("batches")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
        
        guard let dbRow = response.value.first else {
            return nil
        }
        
        return dbRow.toBatch()
    }
    
    // MARK: - Update Batch
    
    /// Update an existing batch
    /// - Parameter batch: Batch with updated values
    /// - Returns: The updated batch
    func updateBatch(_ batch: Batch) async throws -> Batch {
        var updateData: [String: AnyCodable] = [
            "name": AnyCodable(batch.name),
            "qr_type": AnyCodable(batch.qrType.rawValue),
            "export_format": AnyCodable(batch.exportFormat.rawValue)
        ]
        
        if let customURL = batch.customURL {
            updateData["custom_url"] = AnyCodable(customURL)
        } else {
            updateData["custom_url"] = AnyCodable(nil as String?)
        }
        
        let response = try await client
            .from("batches")
            .update(updateData)
            .eq("id", value: batch.id.uuidString)
            .select()
            .execute()
        
        let decoder = createSupabaseDecoder()
        let dbRows: [BatchDBRow] = try decoder.decode([BatchDBRow].self, from: response.data)
        
        guard let dbRow = dbRows.first,
              let updatedBatch = dbRow.toBatch() else {
            throw BatchRepositoryError.updateFailed("No data returned from update or invalid data")
        }
        
        print("✅ [Batch Repository] Batch updated: \(updatedBatch.id)")
        return updatedBatch
    }
    
    // MARK: - Delete Batch
    
    /// Delete a batch
    /// - Parameter id: Batch ID to delete
    func deleteBatch(id: UUID) async throws {
        try await client
            .from("batches")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        
        print("✅ [Batch Repository] Batch deleted: \(id)")
    }
    
    // MARK: - Helper
    
    private func createSupabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Errors

enum BatchRepositoryError: LocalizedError {
    case insertFailed(String)
    case updateFailed(String)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .insertFailed(let message):
            return "Failed to create batch: \(message)"
        case .updateFailed(let message):
            return "Failed to update batch: \(message)"
        case .notFound:
            return "Batch not found"
        }
    }
}



