import Foundation
import Combine
import MapboxMaps
import CoreLocation
import CoreGraphics
import UIKit

// MARK: - Highlight Mode

enum HighlightMode {
  case mapboxProTilequery
  case none
}

@MainActor
final class UseCampaignMap: ObservableObject {

  struct HomePoint: Identifiable {
    let id: UUID
    let address: String
    let coord: CLLocationCoordinate2D
    let number: String? // House number extracted from address
  }

  @Published var homes: [HomePoint] = []
  @Published var isLoading: Bool = false
  @Published var error: String?

  // Address statuses keyed by address_id (as String for consistency with feature-state)
  @Published var addressStatuses: [String: AddressStatus] = [:]

  // GeoJSON cache for building polygons
  @Published var buildingFeatureCollection: FeatureCollection = .init(features: [])
  
  // Building stats for UI display
  @Published var buildingStats: String = "" // "Buildings: X/Y"
  
  // Fetching state for UI feedback
  @Published var isFetchingBuildings: Bool = false

  // Polygon drawing state
  @Published var isDrawingPolygon: Bool = false
  @Published var drawnPolygonVertices: [CLLocationCoordinate2D] = []

  // Feature flag
  var highlightMode: HighlightMode = .mapboxProTilequery
  
  // MapView reference for feature-state updates
  weak var mapView: MapView?
  
  // Store campaign ID for building queries
  private var currentCampaignId: UUID?
  
  private var cancellables = Set<AnyCancellable>()

  func loadHomes(campaignId: UUID, campaign: CampaignV2? = nil) async {
    self.currentCampaignId = campaignId
    isLoading = true; defer { isLoading = false }
    
    // Fetch addresses from database to ensure we have correct DB IDs (campaign_addresses.id)
    let addresses: [CampaignAddressRow]
    
    do {
      // Always fetch from DB to get correct campaign_addresses.id values
      addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaignId)
      print("🗺️ [MAP DEBUG] Loaded \(addresses.count) addresses from database with DB IDs")
    } catch {
      print("⚠️ [MAP DEBUG] Failed to fetch addresses from DB: \(error)")
      self.error = "Failed to load campaign addresses."
      self.homes = []
      return
    }
    
    let points = addresses.compactMap { row in
      HomePoint(
        id: row.id,
        address: row.formatted,
        coord: CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon),
        number: row.formatted.extractHouseNumber()
      )
    }
    self.homes = points
    print("🗺️ [MAP DEBUG] Created \(points.count) HomePoint objects")
    
    // Fetch address statuses for this campaign
    do {
      let statusRows = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignId)
      // Convert to [String: AddressStatus] dictionary for view model
      let statusesDict = Dictionary(uniqueKeysWithValues: statusRows.map { 
        ($0.key.uuidString, $0.value.status) 
      })
      await MainActor.run {
        self.addressStatuses = statusesDict
      }
      print("📊 [MAP DEBUG] Loaded \(statusesDict.count) address statuses")
    } catch {
      print("⚠️ [MAP DEBUG] Failed to fetch address statuses: \(error)")
      // Continue without statuses - buildings will use default colors
    }
  }

  /// Load building polygons using MVT decode Edge Function workflow
  /// Fetches polygons from Supabase cache (via Edge Function if needed)
  func loadFootprints() async {
    guard !homes.isEmpty else {
      print("⚠️ [MVT] No homes to process")
      await createProxiesForAll()
      return
    }
    
    print("🏗️ [MVT] Starting MVT decode workflow for \(homes.count) addresses")
    
    // Convert homes to CampaignAddressRow format
    let addresses = homes.map { home in
      CampaignAddressRow(
        id: home.id,
        formatted: home.address,
        lat: home.coord.latitude,
        lon: home.coord.longitude
      )
    }
    
    do {
      // Step 1: Ensure polygons are cached via Edge Function
      await MainActor.run {
        self.isFetchingBuildings = true
      }
      defer {
        Task { @MainActor in
          self.isFetchingBuildings = false
        }
      }
      
      print("🏗️ [MVT] Ensuring polygons via Edge Function (tiledecode_buildings)...")
      let response = try await BuildingsAPI.shared.ensureBuildingPolygons(addresses: addresses)
      print("✅ [MVT] Edge Function complete: \(response.matched)/\(response.addresses) matched, \(response.proxies) proxies, \(response.created) created, \(response.updated) updated, \(response.total_ms)ms total (\(response.per_addr_ms)ms/addr)")
      
      // Step 1.5: Render features from response immediately if available
      if let responseFeatures = response.features, !responseFeatures.isEmpty {
        print("🏗️ [MVT] Rendering \(responseFeatures.count) features from response immediately")
        
        // Convert GeoJSON features to Mapbox features
        var mapboxFeatures: [Feature] = []
        var filteredCount = 0
        var conversionFailedCount = 0
        
        for geoFeature in responseFeatures {
          // Filter to only Polygon/MultiPolygon
          guard geoFeature.geometry.type == "Polygon" || geoFeature.geometry.type == "MultiPolygon" else {
            filteredCount += 1
            print("⚠️ [MVT] Filtered out geometry type: \(geoFeature.geometry.type)")
            continue
          }
          
          guard let geometry = convertGeoJSONGeometry(geoFeature.geometry) else {
            conversionFailedCount += 1
            print("⚠️ [MVT] Failed to convert geometry for feature from response (type: \(geoFeature.geometry.type))")
            continue
          }
          
          var mapboxFeature = Feature(geometry: geometry)
          // Convert properties from AnyCodable to JSONValue
          var props: [String: JSONValue] = [:]
          for (key, anyCodable) in geoFeature.properties {
            if let stringValue = anyCodable.value as? String {
              props[key] = .string(stringValue)
            } else if let numberValue = anyCodable.value as? Double {
              props[key] = .number(numberValue)
            } else if let intValue = anyCodable.value as? Int {
              props[key] = .number(Double(intValue))
            } else if let boolValue = anyCodable.value as? Bool {
              props[key] = .boolean(boolValue)
            }
          }
          mapboxFeature.properties = props
          mapboxFeatures.append(mapboxFeature)
        }
        
        print("🗺️ [IMMEDIATE RENDER] FeatureCollection count: \(mapboxFeatures.count) (filtered: \(filteredCount), conversion failed: \(conversionFailedCount))")
        
        // Update building stats from response
        let polygonCount = mapboxFeatures.count
        let stats = "Buildings: \(polygonCount)/\(addresses.count)"
        
        // Render immediately
        await MainActor.run {
          self.buildingFeatureCollection = FeatureCollection(features: mapboxFeatures)
          self.buildingStats = stats
        }
        
        print("✅ [MVT] Rendered \(mapboxFeatures.count) features immediately from response")
      } else {
        print("⚠️ [MVT] No features in response to render immediately (features count: \(response.features?.count ?? 0))")
      }
      
      // Diagnostics: if matched == 0, log sample coordinates
      if response.matched == 0 && !addresses.isEmpty {
        let sample = addresses.first!
        print("⚠️ [MVT] No matches found. Sample address: id=\(sample.id), lon=\(sample.lon), lat=\(sample.lat)")
        print("⚠️ [MVT] Check Edge Function logs in Supabase Dashboard for MVT fetch details")
      }
      
      // Step 2: Fetch polygons from database (for persistence and to get any missing ones)
      print("🏗️ [MVT] Fetching polygons from database...")
      let geoJSONCollection: GeoJSONFeatureCollection
      if let campaignId = currentCampaignId {
        // Use campaign-based fetch (queries buildings table where data exists)
        geoJSONCollection = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignId)
      } else {
        // Fallback: fetch by address IDs (legacy)
        let addressIds = homes.map { $0.id }
        geoJSONCollection = try await BuildingsAPI.shared.fetchBuildingPolygons(addressIds: addressIds)
      }
      
      // Step 3: Convert GeoJSONFeatureCollection to Mapbox FeatureCollection
      // Filter to only Polygon/MultiPolygon geometries to prevent FillLayer errors
      let (polygonFeatures, _) = splitFeaturesByGeometry(geoJSONCollection)
      
      var mapboxFeatures: [Feature] = []
      let matchedAddressIds = Set(polygonFeatures.compactMap { feature in
        if let addressIdValue = feature.properties["address_id"] {
          return addressIdValue.value as? String
        }
        return nil
      })
      
      for geoFeature in polygonFeatures {
        guard let geometry = convertGeoJSONGeometry(geoFeature.geometry) else {
          print("⚠️ [MVT] Failed to convert geometry for feature")
          continue
        }
        
        var mapboxFeature = Feature(geometry: geometry)
        // Convert properties from AnyCodable to JSONValue
        var props: [String: JSONValue] = [:]
        for (key, anyCodable) in geoFeature.properties {
          // Convert AnyCodable.value to JSONValue
          if let stringValue = anyCodable.value as? String {
            props[key] = .string(stringValue)
          } else if let numberValue = anyCodable.value as? Double {
            props[key] = .number(numberValue)
          } else if let intValue = anyCodable.value as? Int {
            props[key] = .number(Double(intValue))
          } else if let boolValue = anyCodable.value as? Bool {
            props[key] = .boolean(boolValue)
          }
          // Skip null and other types
        }
        mapboxFeature.properties = props
        mapboxFeatures.append(mapboxFeature)
      }
      
      // Step 4: Create proxy circles for addresses without polygons
      let missingAddressIds = Set(homes.map { $0.id.uuidString }).subtracting(matchedAddressIds)
      var proxyCount = 0
      for home in homes {
        if missingAddressIds.contains(home.id.uuidString) {
          let g = Geometry.polygon(Polygon(center: home.coord, radiusMeters: 3.5, segments: 20))
          var proxyFeature = Feature(geometry: g)
          proxyFeature.properties = [
            "address_id": .string(home.id.uuidString),
            "is_proxy": .boolean(true)
          ]
          mapboxFeatures.append(proxyFeature)
          proxyCount += 1
        }
      }
      
      print("✅ [MVT] Rendering: \(mapboxFeatures.count - proxyCount) polygons, \(proxyCount) proxies")
      
      // Update building stats
      let polygonCount = mapboxFeatures.count - proxyCount
      let stats = "Buildings: \(polygonCount)/\(homes.count)"
      
      await MainActor.run {
        self.buildingFeatureCollection = FeatureCollection(features: mapboxFeatures)
        self.buildingStats = stats
      }
      
    } catch {
      print("❌ [MVT] Error: \(error)")
      // Fallback: render all proxies
      await createProxiesForAll()
    }
  }
  
  /// Split features by geometry type (polygons vs other)
  private func splitFeaturesByGeometry(_ collection: GeoJSONFeatureCollection) -> (polygons: [GeoJSONFeature], others: [GeoJSONFeature]) {
    var polygons: [GeoJSONFeature] = []
    var others: [GeoJSONFeature] = []
    
    for feature in collection.features {
      switch feature.geometry.type {
      case "Polygon", "MultiPolygon":
        polygons.append(feature)
      default:
        others.append(feature)
      }
    }
    
    if others.count > 0 {
      print("⚠️ [MVT] Filtered out \(others.count) non-polygon features (LineString, Point, etc.)")
    }
    
    return (polygons, others)
  }
  
  /// Convert GeoJSONGeometry to Mapbox Geometry
  private func convertGeoJSONGeometry(_ geoGeometry: GeoJSONGeometry) -> Geometry? {
    switch geoGeometry.type {
    case "Polygon":
      guard let coords = geoGeometry.coordinates.value as? [[[Double]]] else { return nil }
      let polygonCoords = coords.map { ring in
        ring.map { coord in
          LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
      }
      return .polygon(Polygon(polygonCoords))
      
    case "MultiPolygon":
      guard let coords = geoGeometry.coordinates.value as? [[[[Double]]]] else { return nil }
      let multiPolygonCoords = coords.map { polygon in
        polygon.map { ring in
          ring.map { coord in
            LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
          }
        }
      }
      return .multiPolygon(MultiPolygon(multiPolygonCoords))
      
    default:
      return nil
    }
  }
  
  /// Create proxy circles for all addresses (fallback when no building layer)
  private func createProxiesForAll() async {
    var features: [Feature] = []
    for h in homes {
      let g = Geometry.polygon(Polygon(center: h.coord, radiusMeters: 3.5, segments: 20))
      var proxyFeature = Feature(geometry: g)
      proxyFeature.properties = ["address_id": .string(h.id.uuidString), "is_proxy": .boolean(true)]
      features.append(proxyFeature)
    }
    await MainActor.run {
      self.buildingFeatureCollection = FeatureCollection(features: features)
    }
  }
  
  /// Load addresses within a drawn polygon via provision flow: save territory → backend (Lambda/S3) provisions → ingest to Supabase → refetch from Supabase.
  /// - Parameters:
  ///   - polygon: Array of coordinates forming the polygon
  ///   - campaignId: Campaign ID (required). Backend reads territory_boundary and provisions via Lambda/S3.
  func loadAddressesInPolygon(polygon: [CLLocationCoordinate2D], campaignId: UUID?) async {
    guard polygon.count >= 3 else {
      print("⚠️ [POLYGON] Polygon must have at least 3 points, got \(polygon.count)")
      return
    }

    guard let campaignId = campaignId else {
      print("⚠️ [POLYGON] Campaign required to provision addresses from polygon")
      await MainActor.run {
        self.error = "Select a campaign to add addresses from this area."
      }
      return
    }

    isLoading = true
    defer { isLoading = false }

    let geoJSONString = polygonToGeoJSON(polygon: polygon)
    print("🗺️ [POLYGON] Provision flow: update territory → provision (backend) → refetch from Supabase")

    do {
      try await CampaignsAPI.shared.updateTerritoryBoundary(campaignId: campaignId, polygonGeoJSON: geoJSONString)
      try await CampaignsAPI.shared.provisionCampaign(campaignId: campaignId)

      let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaignId)
      let newHomePoints = addresses.map { row in
        HomePoint(
          id: row.id,
          address: row.formatted,
          coord: CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon),
          number: row.formatted.extractHouseNumber()
        )
      }

      print("✅ [POLYGON] Refetched \(newHomePoints.count) addresses from Supabase after provision")

      await MainActor.run {
        self.homes = newHomePoints
      }

      if !newHomePoints.isEmpty {
        await loadFootprints()
      }
    } catch {
      print("❌ [POLYGON] Error: \(error)")
      await MainActor.run {
        self.error = "Failed to provision addresses: \(error.localizedDescription)"
      }
    }
  }
  
  /// Convert polygon coordinates to GeoJSON Polygon string
  /// - Parameter polygon: Array of coordinates
  /// - Returns: GeoJSON Polygon string
  private func polygonToGeoJSON(polygon: [CLLocationCoordinate2D]) -> String {
    // Ensure polygon is closed (first point == last point)
    var coords = polygon
    if coords.first != coords.last {
      coords.append(coords.first!)
    }
    
    // Convert to GeoJSON format: [[[lon, lat], [lon, lat], ...]]
    let coordinateArray = coords.map { coord in
      [coord.longitude, coord.latitude]
    }
    
    let geoJSON: [String: Any] = [
      "type": "Polygon",
      "coordinates": [coordinateArray]
    ]
    
    // Convert to JSON string
    guard let jsonData = try? JSONSerialization.data(withJSONObject: geoJSON, options: []),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
      fatalError("Failed to convert polygon to GeoJSON string")
    }
    
    return jsonString
  }
  
}

// MARK: - Geometry helpers

extension Polygon {
  /// Create a circle-like polygon around a center
  init(center: CLLocationCoordinate2D, radiusMeters: Double, segments: Int = 32) {
    let earth = 6_378_137.0
    let dLat = (radiusMeters / earth) * 180.0 / .pi
    let dLon = dLat / cos(center.latitude * .pi / 180.0)
    var coords: [CLLocationCoordinate2D] = []
    for i in 0..<segments {
      let theta = Double(i) * (2.0 * .pi / Double(segments))
      let lat = center.latitude  + dLat * sin(theta)
      let lon = center.longitude + dLon * cos(theta)
      coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
    coords.append(coords.first!)
    self.init([coords.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }])
  }

  /// Rough area in projected degrees (good enough to pick largest building)
  func areaApprox() -> Double {
    guard let ring = coordinates.first else { return 0 }
    guard ring.count > 2 else { return 0 }
    var sum = 0.0
    for i in 0..<(ring.count - 1) {
      let p1 = ring[i]; let p2 = ring[i+1]
      sum += (p1.longitude * p2.latitude - p2.longitude * p1.latitude)
    }
    return abs(sum / 2.0)
  }
}
