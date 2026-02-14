import Foundation
import Supabase

/// Actor-based service for subscribing to real-time building stats updates
/// Uses WebSocket subscriptions with polling fallback for reliability
actor BuildingStatsSubscriber {
    // MARK: - Private Properties
    
    private let supabase: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var pollingTask: Task<Void, Never>?
    private var useWebSocket = true
    private var lastStats: [UUID: BuildingStatsUpdate] = [:]
    
    // MARK: - Callback
    
    /// Called when a building stat is updated
    /// Parameters: (gersId, status, scansTotal, qrScanned)
    var onUpdate: (@Sendable (UUID, String, Int, Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    // MARK: - Public Methods
    
    /// Sets the update callback
    /// - Parameter callback: The callback to invoke when updates are received
    func setUpdateCallback(_ callback: @escaping @Sendable (UUID, String, Int, Bool) -> Void) {
        self.onUpdate = callback
    }
    
    /// Subscribes to building stats updates for a campaign
    /// - Parameter campaignId: The campaign ID to subscribe to
    func subscribe(campaignId: UUID) async {
        // Try WebSocket first
        if useWebSocket {
            await subscribeWebSocket(campaignId: campaignId)
        } else {
            // Fall back to polling
            await subscribeFallback(campaignId: campaignId)
        }
    }
    
    /// Unsubscribes from all updates and cleans up resources
    func unsubscribe() async {
        // Cancel polling task
        pollingTask?.cancel()
        pollingTask = nil
        
        // Unsubscribe from channel
        if let channel = channel {
            await channel.unsubscribe()
            self.channel = nil
        }
        
        // Clear cache
        lastStats.removeAll()
    }
    
    // MARK: - Private Methods - WebSocket
    
    private func subscribeWebSocket(campaignId: UUID) async {
        let channelId = "building-stats-\(campaignId.uuidString)"
        
        do {
            // Create channel
            let newChannel = supabase.realtimeV2.channel(channelId)
            
            // Listen to building_stats changes
            let changeStream = await newChannel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "building_stats"
            )
            
            // Handle updates in a background task
            Task {
                for await change in changeStream {
                    await self.handleWebSocketUpdate(change: change)
                }
            }
            
            // Also listen to updates
            let updateStream = await newChannel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "building_stats"
            )
            
            Task {
                for await change in updateStream {
                    await self.handleWebSocketUpdate(change: change)
                }
            }
            
            // Subscribe to channel
            await newChannel.subscribe()
            self.channel = newChannel
            
            print("✅ BuildingStatsSubscriber: WebSocket connected for campaign \(campaignId)")
        } catch {
            print("⚠️ BuildingStatsSubscriber: WebSocket failed, falling back to polling. Error: \(error)")
            useWebSocket = false
            await subscribeFallback(campaignId: campaignId)
        }
    }
    
    private func handleWebSocketUpdate<T>(change: T) async {
        // Extract data from change
        var gersId: UUID?
        var status: String?
        var scansTotal: Int?
        
        // Try to parse the change payload
        if let mirror = Mirror(reflecting: change).children.first(where: { $0.label == "record" })?.value as? [String: Any] {
            if let gersIdString = mirror["gers_id"] as? String {
                gersId = UUID(uuidString: gersIdString)
            }
            status = mirror["status"] as? String
            scansTotal = mirror["scans_total"] as? Int
        }
        
        guard let gersId = gersId,
              let status = status,
              let scansTotal = scansTotal else {
            return
        }
        
        let qrScanned = scansTotal > 0
        
        // Store in cache
        lastStats[gersId] = BuildingStatsUpdate(
            gersId: gersId,
            status: status,
            scansTotal: scansTotal,
            qrScanned: qrScanned
        )
        
        // Call callback
        onUpdate?(gersId, status, scansTotal, qrScanned)
    }
    
    // MARK: - Private Methods - Polling Fallback
    
    private func subscribeFallback(campaignId: UUID) async {
        print("🔄 BuildingStatsSubscriber: Starting polling mode for campaign \(campaignId)")
        
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    // Fetch current stats
                    let stats = try await fetchBuildingStats(campaignId: campaignId)
                    
                    // Compare with cached values and call onUpdate for changes
                    for stat in stats {
                        let cached = lastStats[stat.gersId]
                        if cached == nil || cached?.scansTotal != stat.scansTotal || cached?.status != stat.status {
                            lastStats[stat.gersId] = stat
                            onUpdate?(stat.gersId, stat.status, stat.scansTotal, stat.qrScanned)
                        }
                    }
                    
                    // Sleep for 5 seconds before next poll
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    if !Task.isCancelled {
                        print("⚠️ BuildingStatsSubscriber: Polling error: \(error)")
                        // Sleep a bit before retrying
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }
        }
    }
    
    private func fetchBuildingStats(campaignId: UUID) async throws -> [BuildingStatsUpdate] {
        let response = try await supabase
            .from("building_stats")
            .select("gers_id, status, scans_total")
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode([BuildingStatsUpdate].self, from: response.data)
    }
}

// MARK: - Supporting Types

private struct BuildingStatsUpdate: Codable {
    let gersId: UUID
    let status: String
    let scansTotal: Int
    let qrScanned: Bool
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case status
        case scansTotal = "scans_total"
    }
    
    init(gersId: UUID, status: String, scansTotal: Int, qrScanned: Bool) {
        self.gersId = gersId
        self.status = status
        self.scansTotal = scansTotal
        self.qrScanned = qrScanned
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gersId = try container.decode(UUID.self, forKey: .gersId)
        status = try container.decode(String.self, forKey: .status)
        scansTotal = try container.decode(Int.self, forKey: .scansTotal)
        qrScanned = scansTotal > 0
    }
}

// MARK: - Convenience

extension BuildingStatsSubscriber {
    /// Creates a BuildingStatsSubscriber using the shared Supabase manager
    static var shared: BuildingStatsSubscriber {
        BuildingStatsSubscriber(supabase: SupabaseManager.shared.client)
    }
}
