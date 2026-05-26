import Foundation
import Supabase

/// Actor-based service for subscribing to real-time building stats updates
/// Uses WebSocket subscriptions with polling fallback for reliability
actor BuildingStatsSubscriber {
    // MARK: - Private Properties
    
    private let supabase: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var pollingTask: Task<Void, Never>?
    private var insertStreamTask: Task<Void, Never>?
    private var updateStreamTask: Task<Void, Never>?
    private var useWebSocket = true
    private var lastStats: [String: BuildingStatsUpdate] = [:]
    private var subscribedCampaignId: UUID?
    private var isSubscribing = false
    
    // MARK: - Callback
    
    /// Called when a building stat is updated
    /// Parameters: (gersId string, status, scansTotal, qrScanned)
    var onUpdate: (@Sendable (String, String, Int, Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    // MARK: - Public Methods
    
    /// Sets the update callback
    /// - Parameter callback: The callback to invoke when updates are received
    func setUpdateCallback(_ callback: @escaping @Sendable (String, String, Int, Bool) -> Void) {
        self.onUpdate = callback
    }
    
    /// Subscribes to building stats updates for a campaign
    /// - Parameter campaignId: The campaign ID to subscribe to
    func subscribe(campaignId: UUID) async {
        if subscribedCampaignId == campaignId, isSubscribing || channel != nil || pollingTask != nil {
            return
        }
        await unsubscribe()
        subscribedCampaignId = campaignId
        isSubscribing = true
        defer { isSubscribing = false }

        guard NetworkMonitor.shared.isOnline else {
            print("📴 BuildingStatsSubscriber: Skipping subscribe while offline for campaign \(campaignId)")
            subscribedCampaignId = nil
            return
        }

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
        isSubscribing = false

        // Cancel polling task
        pollingTask?.cancel()
        pollingTask = nil
        insertStreamTask?.cancel()
        insertStreamTask = nil
        updateStreamTask?.cancel()
        updateStreamTask = nil
        
        // Unsubscribe from channel
        if let channel = channel {
            await supabase.realtimeV2.removeChannel(channel)
            self.channel = nil
        }
        
        // Clear cache
        lastStats.removeAll()
        subscribedCampaignId = nil
    }
    
    // MARK: - Private Methods - WebSocket
    
    private func subscribeWebSocket(campaignId: UUID) async {
        let channelId = "building-stats-\(campaignId.uuidString)-\(UUID().uuidString)"
        
        // Create channel
        let newChannel = supabase.realtimeV2.channel(channelId)
        
        // Listen to only this campaign's building_stats changes.
        let changeStream = newChannel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "building_stats",
            filter: .eq("campaign_id", value: campaignId.uuidString)
        )
        
        // Handle updates in a background task
        insertStreamTask = Task {
            for await change in changeStream {
                await self.handleWebSocketUpdate(change: change)
            }
        }

        // Subscribe to channel
        do {
            try await newChannel.subscribeWithError()
            guard subscribedCampaignId == campaignId, isSubscribing else {
                await supabase.realtimeV2.removeChannel(newChannel)
                return
            }
            self.channel = newChannel
            print("✅ BuildingStatsSubscriber: WebSocket connected for campaign \(campaignId)")
        } catch {
            guard subscribedCampaignId == campaignId, isSubscribing else {
                await supabase.realtimeV2.removeChannel(newChannel)
                return
            }
            print("⚠️ BuildingStatsSubscriber: WebSocket subscribe failed: \(error). Falling back to polling.")
            useWebSocket = false
            insertStreamTask?.cancel()
            insertStreamTask = nil
            updateStreamTask?.cancel()
            updateStreamTask = nil
            await supabase.realtimeV2.removeChannel(newChannel)
            await subscribeFallback(campaignId: campaignId)
        }
    }
    
    private func handleWebSocketUpdate(change: AnyAction) async {
        let record: [String: AnyJSON]
        switch change {
        case .insert(let insert):
            record = insert.record
        case .update(let update):
            record = update.record
        case .delete:
            return
        }
        
        guard let gersId = record["gers_id"]?.stringValue, !gersId.isEmpty,
              let status = record["status"]?.stringValue else {
            return
        }
        let scansTotal = record["scans_total"]?.intValue
            ?? Int(record["scans_total"]?.doubleValue ?? 0)
        
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
                guard NetworkMonitor.shared.isOnline else {
                    print("📴 BuildingStatsSubscriber: Pausing polling while offline")
                    return
                }

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
    let gersId: String
    let status: String
    let scansTotal: Int
    let qrScanned: Bool
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case status
        case scansTotal = "scans_total"
    }
    
    init(gersId: String, status: String, scansTotal: Int, qrScanned: Bool) {
        self.gersId = gersId
        self.status = status
        self.scansTotal = scansTotal
        self.qrScanned = qrScanned
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gersId = try container.decode(String.self, forKey: .gersId)
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
