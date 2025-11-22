import Foundation
import Supabase

/// API layer for A/B test experiment operations
actor ExperimentsAPI {
    static let shared = ExperimentsAPI()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch Experiments
    
    /// Fetch all experiments for the current user's campaigns
    func fetchExperiments() async throws -> [Experiment] {
        let session = try await client.auth.session
        let userId = session.user.id
        
        // Fetch experiments where the campaign belongs to the user
        let response: PostgrestResponse<[Experiment]> = try await client
            .from("experiments")
            .select("""
                id, campaign_id, landing_page_id, name, status, created_at,
                campaigns!inner(owner_id)
            """)
            .eq("campaigns.owner_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        return response.value
    }
    
    /// Fetch a single experiment by ID
    func fetchExperiment(id: UUID) async throws -> Experiment {
        let response: PostgrestResponse<Experiment> = try await client
            .from("experiments")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        
        return response.value
    }
    
    // MARK: - Fetch Variants
    
    /// Fetch all variants for an experiment
    func fetchVariants(experimentId: UUID) async throws -> [ExperimentVariant] {
        let response: PostgrestResponse<[ExperimentVariant]> = try await client
            .from("experiment_variants")
            .select()
            .eq("experiment_id", value: experimentId.uuidString)
            .order("key", ascending: true)
            .execute()
        
        return response.value
    }
    
    // MARK: - Create Experiment
    
    /// Create a new experiment
    /// - Parameters:
    ///   - name: Experiment name
    ///   - campaignId: Associated campaign ID
    ///   - landingPageId: Associated landing page ID
    /// - Returns: The created experiment
    func createExperiment(name: String, campaignId: UUID, landingPageId: UUID) async throws -> Experiment {
        let experimentData: [String: AnyCodable] = [
            "campaign_id": AnyCodable(campaignId.uuidString),
            "landing_page_id": AnyCodable(landingPageId.uuidString),
            "name": AnyCodable(name),
            "status": AnyCodable("draft")
        ]
        
        let response: PostgrestResponse<Experiment> = try await client
            .from("experiments")
            .insert(experimentData)
            .select()
            .single()
            .execute()
        
        return response.value
    }
    
    // MARK: - Create Variants
    
    /// Create Variant A and Variant B for an experiment
    /// Generates unique slugs for each variant
    /// - Parameter experimentId: Experiment ID
    /// - Returns: Array of created variants [Variant A, Variant B]
    func createVariants(experimentId: UUID) async throws -> [ExperimentVariant] {
        // Generate unique slugs for both variants
        let slugA = SlugGenerator.generateUniqueSlug()
        let slugB = SlugGenerator.generateUniqueSlug()
        
        // Ensure slugs are unique (retry if collision, though unlikely)
        var finalSlugA = slugA
        var finalSlugB = slugB
        while finalSlugA == finalSlugB {
            finalSlugB = SlugGenerator.generateUniqueSlug()
        }
        
        let variantsData: [[String: AnyCodable]] = [
            [
                "experiment_id": AnyCodable(experimentId.uuidString),
                "key": AnyCodable("A"),
                "url_slug": AnyCodable(finalSlugA)
            ],
            [
                "experiment_id": AnyCodable(experimentId.uuidString),
                "key": AnyCodable("B"),
                "url_slug": AnyCodable(finalSlugB)
            ]
        ]
        
        let response: PostgrestResponse<[ExperimentVariant]> = try await client
            .from("experiment_variants")
            .insert(variantsData)
            .select()
            .order("key", ascending: true)
            .execute()
        
        return response.value
    }
    
    // MARK: - Fetch Statistics
    
    /// Fetch scan statistics for an experiment
    /// - Parameter experimentId: Experiment ID
    /// - Returns: Statistics including scans, unique visitors, and conversions for both variants
    func fetchScanStats(experimentId: UUID) async throws -> ExperimentScanStats {
        // Fetch variant IDs first
        let variants = try await fetchVariants(experimentId: experimentId)
        guard let variantA = variants.first(where: { $0.key == "A" }),
              let variantB = variants.first(where: { $0.key == "B" }) else {
            // Return empty stats if variants don't exist
            return ExperimentScanStats()
        }
        
        // Count scans for variant A
        let scansA: PostgrestResponse<[QRScanEventRow]> = try await client
            .from("qr_scan_events")
            .select("id")
            .eq("variant_id", value: variantA.id.uuidString)
            .execute()
        
        let variantA_scans = scansA.value.count
        
        // Count scans for variant B
        let scansB: PostgrestResponse<[QRScanEventRow]> = try await client
            .from("qr_scan_events")
            .select("id")
            .eq("variant_id", value: variantB.id.uuidString)
            .execute()
        
        let variantB_scans = scansB.value.count
        
        // Count unique visitors (by device_type or other identifier)
        // For now, we'll use a simple count - in production you'd want to count distinct devices
        let uniqueA: PostgrestResponse<[QRScanEventRow]> = try await client
            .from("qr_scan_events")
            .select("device_type")
            .eq("variant_id", value: variantA.id.uuidString)
            .execute()
        
        let variantA_unique = Set(uniqueA.value.compactMap { $0.deviceType }).count
        
        let uniqueB: PostgrestResponse<[QRScanEventRow]> = try await client
            .from("qr_scan_events")
            .select("device_type")
            .eq("variant_id", value: variantB.id.uuidString)
            .execute()
        
        let variantB_unique = Set(uniqueB.value.compactMap { $0.deviceType }).count
        
        // Count conversions for variant A
        let conversionsA: PostgrestResponse<[ConversionRow]> = try await client
            .from("conversions")
            .select("id")
            .eq("variant_id", value: variantA.id.uuidString)
            .execute()
        
        let variantA_conversions = conversionsA.value.count
        
        // Count conversions for variant B
        let conversionsB: PostgrestResponse<[ConversionRow]> = try await client
            .from("conversions")
            .select("id")
            .eq("variant_id", value: variantB.id.uuidString)
            .execute()
        
        let variantB_conversions = conversionsB.value.count
        
        return ExperimentScanStats(
            variantA_scans: variantA_scans,
            variantB_scans: variantB_scans,
            variantA_unique: variantA_unique,
            variantB_unique: variantB_unique,
            variantA_conversions: variantA_conversions,
            variantB_conversions: variantB_conversions
        )
    }
    
    // MARK: - Update Experiment
    
    /// Update experiment status
    /// - Parameters:
    ///   - experimentId: Experiment ID
    ///   - status: New status ("draft", "running", "completed")
    func updateExperimentStatus(experimentId: UUID, status: String) async throws {
        let updateData: [String: AnyCodable] = [
            "status": AnyCodable(status)
        ]
        
        _ = try await client
            .from("experiments")
            .update(updateData)
            .eq("id", value: experimentId.uuidString)
            .execute()
    }
    
    /// Mark experiment winner
    /// - Parameters:
    ///   - experimentId: Experiment ID
    ///   - winnerVariantId: ID of the winning variant
    func markExperimentWinner(experimentId: UUID, winnerVariantId: UUID) async throws {
        // Update experiment status to completed
        try await updateExperimentStatus(experimentId: experimentId, status: "completed")
        
        // In the future, you might want to store the winner in the experiments table
        // For now, we just mark it as completed
    }
    
    // MARK: - Delete Experiment
    
    /// Delete an experiment (cascades to variants)
    /// - Parameter id: Experiment ID
    func deleteExperiment(id: UUID) async throws {
        _ = try await client
            .from("experiments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Helper Types
    
    /// Internal row type for scan events query
    private struct QRScanEventRow: Codable {
        let id: UUID?
        let deviceType: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case deviceType = "device_type"
        }
    }
    
    /// Internal row type for conversions query
    private struct ConversionRow: Codable {
        let id: UUID
    }
}

