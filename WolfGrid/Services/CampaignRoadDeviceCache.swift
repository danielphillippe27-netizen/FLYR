import Foundation
import CoreLocation

// MARK: - Local Cache Types

/// Local cache metadata for a campaign's roads
struct LocalRoadCacheMetadata: Codable, Sendable {
    let campaignId: String
    let cacheVersion: Int
    let corridorBuildVersion: Int
    let storedAt: Date
    let expiresAt: Date
    let roadCount: Int
}

/// Cached road data
struct CachedRoad: Codable, Sendable {
    let id: String
    let polyline: [CLLocationCoordinate2D]
    let roadName: String?
    let roadClass: String?
    
    init(id: String, polyline: [CLLocationCoordinate2D], roadName: String? = nil, roadClass: String? = nil) {
        self.id = id
        self.polyline = polyline
        self.roadName = roadName
        self.roadClass = roadClass
    }
}

// MARK: - Campaign Road Device Cache

/// Local device cache for campaign roads (offline mirror).
/// 
/// This is NOT the source of truth - Supabase is.
/// This cache provides:
/// - Fast session startup (no network call)
/// - Offline session support
/// - Reduced API load
actor CampaignRoadDeviceCache {
    static let shared = CampaignRoadDeviceCache()
    
    private let fileManager = FileManager.default
    private let cacheDirectoryName = "CampaignRoadCache"
    private let metadataFileName = "cache_metadata.json"
    private let defaultTTLDays = 30
    private let maxCacheSizeMB = 100
    
    private init() {}
    
    // MARK: - Cache Directory
    
    private var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent(cacheDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func campaignCacheFile(campaignId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(campaignId).json")
    }
    
    private var metadataFile: URL {
        cacheDirectory.appendingPathComponent(metadataFileName)
    }
    
    // MARK: - Store
    
    /// Store roads from StreetCorridors (after fetching from Supabase)
    func store(corridors: [StreetCorridor], campaignId: String, version: Int) {
        let cachedRoads = corridors.map { corridor -> CachedRoad in
            CachedRoad(
                id: corridor.id ?? UUID().uuidString,
                polyline: corridor.polyline,
                roadName: corridor.roadName,
                roadClass: corridor.roadClass
            )
        }
        
        let metadata = LocalRoadCacheMetadata(
            campaignId: campaignId,
            cacheVersion: version,
            corridorBuildVersion: 1,
            storedAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(defaultTTLDays * 24 * 60 * 60)),
            roadCount: cachedRoads.count
        )
        
        do {
            // Store roads
            let roadsData = try JSONEncoder().encode(cachedRoads)
            try roadsData.write(to: campaignCacheFile(campaignId: campaignId))
            
            // Update metadata
            var allMetadata = loadAllMetadata()
            allMetadata[campaignId] = metadata
            try saveAllMetadata(allMetadata)
            
            print("✅ [RoadDeviceCache] Stored \(cachedRoads.count) roads for campaign \(campaignId) (v\(version))")
            
            // Cleanup old caches if needed
            cleanupIfNeeded()
            
        } catch {
            print("❌ [RoadDeviceCache] Failed to store: \(error)")
        }
    }
    
    /// Store roads from RoadFeature objects (after Mapbox fetch)
    func store(roads: [StreetCorridor], campaignId: String, version: Int) {
        // Same implementation as above
        store(corridors: roads, campaignId: campaignId, version: version)
    }
    
    // MARK: - Load
    
    /// Load roads for a campaign
    func load(campaignId: String) -> [StreetCorridor]? {
        // Check if cache is valid
        guard let metadata = loadMetadata(campaignId: campaignId) else {
            return nil
        }
        
        // Check expiration
        if Date() > metadata.expiresAt {
            print("⚠️ [RoadDeviceCache] Cache expired for campaign \(campaignId)")
            Task { await clear(campaignId: campaignId) }
            return nil
        }
        
        // Load roads
        do {
            let data = try Data(contentsOf: campaignCacheFile(campaignId: campaignId))
            let cachedRoads = try JSONDecoder().decode([CachedRoad].self, from: data)
            
            let corridors = cachedRoads.map { road in
                StreetCorridor(id: road.id, polyline: road.polyline, roadName: road.roadName, roadClass: road.roadClass)
            }
            let normalizedCorridors = StreetCorridor.ensuringUniqueIds(corridors)
            if normalizedCorridors.map(\.id) != corridors.map(\.id) {
                print("🛣️ [RoadDeviceCache] Normalized duplicate corridor IDs for campaign \(campaignId)")
            }
            
            return normalizedCorridors
            
        } catch {
            print("❌ [RoadDeviceCache] Failed to load: \(error)")
            return nil
        }
    }
    
    /// Load metadata for a campaign
    func loadMetadata(campaignId: String) -> LocalRoadCacheMetadata? {
        let allMetadata = loadAllMetadata()
        return allMetadata[campaignId]
    }
    
    /// Check if valid cache exists
    func hasValidCache(campaignId: String) -> Bool {
        guard let metadata = loadMetadata(campaignId: campaignId) else {
            return false
        }
        return Date() <= metadata.expiresAt
    }
    
    /// Get cache version for a campaign
    func cacheVersion(campaignId: String) -> Int? {
        loadMetadata(campaignId: campaignId)?.cacheVersion
    }
    
    // MARK: - Clear
    
    /// Clear cache for a specific campaign
    func clear(campaignId: String) {
        do {
            try fileManager.removeItem(at: campaignCacheFile(campaignId: campaignId))
            
            var allMetadata = loadAllMetadata()
            allMetadata.removeValue(forKey: campaignId)
            try saveAllMetadata(allMetadata)
            
            print("✅ [RoadDeviceCache] Cleared cache for campaign \(campaignId)")
        } catch {
            print("⚠️ [RoadDeviceCache] Failed to clear: \(error)")
        }
    }
    
    /// Clear all expired caches
    func clearExpired() {
        let allMetadata = loadAllMetadata()
        let now = Date()
        
        for (campaignId, metadata) in allMetadata {
            if now > metadata.expiresAt {
                Task { await clear(campaignId: campaignId) }
            }
        }
    }
    
    /// Clear all caches
    func clearAll() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
            print("✅ [RoadDeviceCache] Cleared all caches")
        } catch {
            print("❌ [RoadDeviceCache] Failed to clear all: \(error)")
        }
    }
    
    // MARK: - Metadata Management
    
    private func loadAllMetadata() -> [String: LocalRoadCacheMetadata] {
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: metadataFile)
            return try JSONDecoder().decode([String: LocalRoadCacheMetadata].self, from: data)
        } catch {
            print("⚠️ [RoadDeviceCache] Failed to load metadata: \(error)")
            return [:]
        }
    }
    
    private func saveAllMetadata(_ metadata: [String: LocalRoadCacheMetadata]) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataFile)
    }
    
    // MARK: - Cache Management
    
    /// Get total cache size in MB
    private func cacheSizeMB() -> Double {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            
            for url in contents {
                if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
            
            return Double(totalSize) / (1024 * 1024)
        } catch {
            return 0
        }
    }
    
    /// Cleanup old caches if size exceeds limit
    private func cleanupIfNeeded() {
        let sizeMB = cacheSizeMB()
        guard sizeMB > Double(maxCacheSizeMB) else { return }
        
        print("🧹 [RoadDeviceCache] Cache size \(Int(sizeMB))MB exceeds limit, cleaning up...")
        
        let allMetadata = loadAllMetadata()
        
        // Sort by storedAt (oldest first)
        let sorted = allMetadata.sorted { $0.value.storedAt < $1.value.storedAt }
        
        // Remove oldest until under limit
        var currentSize = sizeMB
        for (campaignId, _) in sorted {
            guard currentSize > Double(maxCacheSizeMB * 3 / 4) else { break }
            
            // Get file size before removing
            let fileURL = campaignCacheFile(campaignId: campaignId)
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? Int64 {
                clear(campaignId: campaignId)
                currentSize -= Double(size) / (1024 * 1024)
            }
        }
        
        print("✅ [RoadDeviceCache] Cleanup complete, size now \(Int(currentSize))MB")
    }
    
    /// Get all cached campaign IDs
    func cachedCampaignIds() -> [String] {
        Array(loadAllMetadata().keys)
    }
    
    /// Get cache statistics
    func statistics() -> (campaignCount: Int, totalSizeMB: Double, oldestCache: Date?) {
        let allMetadata = loadAllMetadata()
        let sizeMB = cacheSizeMB()
        let oldest = allMetadata.values.map { $0.storedAt }.min()
        return (allMetadata.count, sizeMB, oldest)
    }
}
