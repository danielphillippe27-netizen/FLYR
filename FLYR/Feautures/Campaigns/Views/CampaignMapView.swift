import SwiftUI
import MapboxMaps
import CoreLocation

struct CampaignMapView: UIViewRepresentable {
  @ObservedObject var vm: UseCampaignMap
  var centerCoordinate: CLLocationCoordinate2D?
  @Binding var isDrawingPolygon: Bool
  var onPolygonComplete: (([CLLocationCoordinate2D]) -> Void)?
  var onAddressTapped: ((String) -> Void)? = nil

  func makeUIView(context: Context) -> MapView {
    // Give MapView a real frame instead of .zero to prevent {64,64} warnings
    let mv = MapView(frame: CGRect(x: 0, y: 0, width: 320, height: 260))
    mv.ornaments.options.scaleBar.visibility = .hidden
    mv.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
    mv.ornaments.options.compass.visibility = .adaptive

    mv.mapboxMap.onNext(event: .mapLoaded) { _ in
      print("🗺️ [MAP] mapLoaded event fired - starting initialization")
      
      // Add our sources/layers once
      context.coordinator.installSourcesAndLayers(on: mv)
      
      // Draw current data
      context.coordinator.updateHomes(vm.homes, on: mv)
      context.coordinator.updateBuildings(vm.buildingFeatureCollection, on: mv)

      // Fit camera to homes or center coordinate (for initial view)
      if let center = centerCoordinate {
        // Use center coordinate if provided
        mv.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15))
        context.coordinator.lastCenterCoordinate = center
        print("🗺️ [MAP] Initial camera set to center: \(center)")
      } else if !vm.homes.isEmpty {
        context.coordinator.fitCameraToHomes(vm.homes, on: mv, centerCoordinate: nil)
      }

      // Don't call loadFootprints here - it will be called after loadHomes completes
    }
    
    // Set up coordinator with callbacks
    context.coordinator.onPolygonComplete = onPolygonComplete
    context.coordinator.onAddressTapped = onAddressTapped
    context.coordinator.mapView = mv
    
    // Store MapView reference in view model for status updates
    vm.mapView = mv
    
    // Add tap gesture recognizer for polygon drawing
    // Set it to require other gesture recognizers to fail so it doesn't interfere with map panning
    let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
    tapGesture.numberOfTapsRequired = 1
    tapGesture.numberOfTouchesRequired = 1
    // Don't require other gestures to fail - we'll check drawing mode in the handler
    mv.addGestureRecognizer(tapGesture)
    print("✅ [POLYGON] Tap gesture recognizer added to map")

    return mv
  }

  func updateUIView(_ mv: MapView, context: Context) {
    context.coordinator.updateHomes(vm.homes, on: mv)
    context.coordinator.updateBuildings(vm.buildingFeatureCollection, on: mv)
    
    // Sync drawing mode with binding
    let wasDrawing = context.coordinator.isDrawingMode
    context.coordinator.isDrawingMode = isDrawingPolygon
    
    // Update mapView reference if needed
    if context.coordinator.mapView == nil {
      context.coordinator.mapView = mv
    }
    
    // Log drawing mode changes
    if wasDrawing != isDrawingPolygon {
      print("🔄 [POLYGON] Drawing mode changed: \(wasDrawing) -> \(isDrawingPolygon)")
    }
    
    // If drawing mode was just disabled, finalize polygon first if it has enough vertices
    if wasDrawing && !isDrawingPolygon {
      if context.coordinator.polygonVertices.count >= 3 {
        context.coordinator.finalizePolygon(on: mv)
      } else {
        context.coordinator.clearPolygon(on: mv)
      }
    }
    
    // Update camera when centerCoordinate changes
    if let center = centerCoordinate {
      context.coordinator.updateCameraIfNeeded(to: center, on: mv, homes: vm.homes)
    } else if !vm.homes.isEmpty {
      // If no center coordinate but we have homes, fit to homes
      context.coordinator.fitCameraToHomes(vm.homes, on: mv, centerCoordinate: nil)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    // 💥 REMOVED: homeSourceId and homeLayerId - no longer using white circle markers
    private let bldgSourceId = "campaign-bldg-src"
    private let bldgFillId   = "campaign-bldg-fill"
    private let bldgLineId   = "campaign-bldg-line"
    
    // Pin source and layer IDs for numbered pins
    private let sourceCampaignPins = "campaign-pins-source"
    private let layerCampaignPins = "campaign-pins-layer"
    
    // Polygon drawing state
    var isDrawingMode: Bool = false
    var polygonVertices: [CLLocationCoordinate2D] = []
    var onPolygonComplete: (([CLLocationCoordinate2D]) -> Void)?
    var onAddressTapped: ((String) -> Void)?
    weak var mapView: MapView?
    
    /// Finalize the current polygon if it has enough vertices
    func tryFinalizePolygon() {
      guard let mapView = mapView else { return }
      finalizePolygon(on: mapView)
    }
    
    // Polygon overlay source/layer IDs
    private let drawPolygonSourceId = "draw-polygon-source"
    private let drawPolygonFillId = "draw-polygon-fill"
    private let drawPolygonLineId = "draw-polygon-line"
    
    // Track last center coordinate to avoid unnecessary camera updates
    var lastCenterCoordinate: CLLocationCoordinate2D?

    func installSourcesAndLayers(on mv: MapView) {
      // 💥 REMOVED: White circle markers - no longer needed
      // Buildings only: red fill with thin border
      
      // Buildings - Red fill with thin border
      var bsrc = GeoJSONSource(id: bldgSourceId)
      bsrc.data = .featureCollection(FeatureCollection(features: []))
      try? mv.mapboxMap.addSource(bsrc)

      // Red fill layer
      var fill = FillLayer(id: bldgFillId, source: bldgSourceId)
      fill.fillColor = .constant(StyleColor(.red))
      fill.fillOpacity = .constant(0.25) // 25% opacity for map visibility
      fill.fillOutlineColor = .constant(StyleColor(.clear)) // Outline handled by line layer
      fill.filter = Exp(.match) {
        Exp(.geometryType)
        "Polygon"
        true
        "MultiPolygon"
        true
        false
      }
      try? mv.mapboxMap.addLayer(fill)

      // Thin red outline layer
      var line = LineLayer(id: bldgLineId, source: bldgSourceId)
      line.lineColor = .constant(StyleColor(.red))
      line.lineWidth = .constant(1.5) // Thin border
      line.lineOpacity = .constant(1.0) // Full opacity
      line.lineJoin = .constant(.round) // Round joins for crisp edges
      line.lineCap = .constant(.round) // Round caps for crisp edges
      line.filter = Exp(.match) {
        Exp(.geometryType)
        "Polygon"
        true
        "MultiPolygon"
        true
        false
      }
      try? mv.mapboxMap.addLayer(line, layerPosition: .above(bldgFillId))
      
      // Campaign pins - Numbered pins like Google Maps
      var pinSource = GeoJSONSource(id: sourceCampaignPins)
      pinSource.data = .featureCollection(FeatureCollection(features: []))
      try? mv.mapboxMap.addSource(pinSource)
      
      // Pin icon layer - using circle for pin shape with house number text
      var pinLayer = SymbolLayer(id: layerCampaignPins, source: sourceCampaignPins)
      
      // Use a circle shape for the pin (simple and reliable)
      // We'll use text-only approach: circle via text background + number text
      // Alternative: use iconImage with a custom asset, but circle is simpler for now
      pinLayer.iconImage = .constant(.name("mapbox-marker-icon-blue"))
      pinLayer.iconSize = .constant(1.0)
      pinLayer.iconAllowOverlap = .constant(true)
      pinLayer.iconIgnorePlacement = .constant(true)
      pinLayer.iconAnchor = .constant(.bottom) // Pin point at bottom
      
      // Text layer for house numbers - displayed on/above the pin
      pinLayer.textField = .expression(Exp(.get) { "number" })
      pinLayer.textSize = .constant(11)
      pinLayer.textColor = .constant(StyleColor(.white))
      pinLayer.textHaloColor = .constant(StyleColor(.black))
      pinLayer.textHaloWidth = .constant(1.5)
      pinLayer.textAllowOverlap = .constant(true)
      pinLayer.textIgnorePlacement = .constant(true)
      pinLayer.textAnchor = .constant(.center)
      pinLayer.textOffset = .constant([0, -2.0]) // Position text in center of icon
      pinLayer.textOptional = .constant(false) // Always show text if number exists
      
      // Add pin layer above building layers so pins are always visible
      // Pins should be visible in both 2D and 3D modes
      try? mv.mapboxMap.addLayer(pinLayer, layerPosition: .above(bldgLineId))
      print("✅ [PINS] Added numbered pin layer (visible in 2D and 3D modes)")
    }

    func updateHomes(_ homes: [UseCampaignMap.HomePoint], on mv: MapView) {
      // Create pin features from homes array
      var pinFeatures: [Feature] = []
      
      for home in homes {
        // Create point geometry - convert CLLocationCoordinate2D to LocationCoordinate2D
        let locationCoord = LocationCoordinate2D(latitude: home.coord.latitude, longitude: home.coord.longitude)
        let point = Point(locationCoord)
        var feature = Feature(geometry: .point(point))
        
        // Use address_id (home.id) as featureId for consistent feature-state keying
        let addressIdString = home.id.uuidString
        feature.identifier = .string(addressIdString)
        
        // Add properties: address_id (for consistency with buildings), id (for backward compat), number (house number), address
        var properties: [String: JSONValue] = [
          "address_id": .string(addressIdString), // Primary key for feature-state
          "id": .string(addressIdString), // Backward compatibility
          "address": .string(home.address)
        ]
        
        // Add house number if available
        if let number = home.number {
          properties["number"] = .string(number)
        }
        
        feature.properties = properties
        pinFeatures.append(feature)
      }
      
      // Update pin source with new features
      let pinFeatureCollection = FeatureCollection(features: pinFeatures)
      do {
        try mv.mapboxMap.updateGeoJSONSource(withId: sourceCampaignPins, geoJSON: .featureCollection(pinFeatureCollection))
        print("✅ [PINS] Updated \(pinFeatures.count) pin features")
      } catch {
        print("❌ [PINS] Failed to update pin source: \(error)")
      }
    }

    func updateBuildings(_ fc: FeatureCollection, on mv: MapView) {
      // Filter to only polygons to prevent FillBucket errors
      let polygonFeatures = fc.features.filter { feature in
        switch feature.geometry {
        case .polygon, .multiPolygon:
          return true
        default:
          print("⚠️ [UPDATE] Filtering out non-polygon geometry: \(feature.geometry)")
          return false
        }
      }
      
      if polygonFeatures.count != fc.features.count {
        print("⚠️ [UPDATE] Filtered out \(fc.features.count - polygonFeatures.count) non-polygon features")
      }
      
      let filteredFC = FeatureCollection(features: polygonFeatures)
      try? mv.mapboxMap.updateGeoJSONSource(withId: bldgSourceId, geoJSON: .featureCollection(filteredFC))
    }
    
    /// Fit camera to all homes with padding (optional, for initial view)
    func fitCameraToHomes(_ homes: [UseCampaignMap.HomePoint], on mv: MapView, centerCoordinate: CLLocationCoordinate2D?) {
      guard !homes.isEmpty else { return }
      
      // If centerCoordinate is provided, use it; otherwise compute bounding box
      if let center = centerCoordinate {
        mv.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15))
        return
      }
      
      // Compute bounding box of all homes
      var minLat = Double.infinity
      var maxLat = -Double.infinity
      var minLon = Double.infinity
      var maxLon = -Double.infinity
      
      for home in homes {
        minLat = min(minLat, home.coord.latitude)
        maxLat = max(maxLat, home.coord.latitude)
        minLon = min(minLon, home.coord.longitude)
        maxLon = max(maxLon, home.coord.longitude)
      }
      
      // Add padding (10% on each side)
      let latPadding = (maxLat - minLat) * 0.1
      let lonPadding = (maxLon - minLon) * 0.1
      
      minLat -= latPadding
      maxLat += latPadding
      minLon -= lonPadding
      maxLon += lonPadding
      
      // Compute center and zoom
      let centerLat = (minLat + maxLat) / 2.0
      let centerLon = (minLon + maxLon) / 2.0
      let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
      
      // Estimate zoom level to fit bounding box
      let latSpan = maxLat - minLat
      let lonSpan = maxLon - minLon
      let maxSpan = max(latSpan, lonSpan)
      
      // Approximate zoom: smaller span = higher zoom
      var zoom: Double = 15.0
      if maxSpan > 0.1 {
        zoom = 12.0
      } else if maxSpan > 0.05 {
        zoom = 13.0
      } else if maxSpan > 0.02 {
        zoom = 14.0
      } else if maxSpan > 0.01 {
        zoom = 15.0
      } else {
        zoom = 16.0
      }
      
      mv.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: zoom))
    }
    
    /// Update camera to center coordinate if it has changed
    func updateCameraIfNeeded(to center: CLLocationCoordinate2D, on mv: MapView, homes: [UseCampaignMap.HomePoint]) {
      // Only update if center coordinate has changed
      if let lastCenter = lastCenterCoordinate,
         abs(lastCenter.latitude - center.latitude) < 0.0001,
         abs(lastCenter.longitude - center.longitude) < 0.0001 {
        return // Center hasn't changed significantly
      }
      
      lastCenterCoordinate = center
      
      // Use center coordinate with appropriate zoom
      if !homes.isEmpty {
        // If we have homes, use the center coordinate with zoom 15
        mv.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15))
        print("🗺️ [MAP] Updated camera to center: \(center)")
      } else {
        // If no homes yet, still center on the coordinate
        mv.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15))
        print("🗺️ [MAP] Updated camera to center (no homes yet): \(center)")
      }
    }
    
    // MARK: - Polygon Drawing
    
    @objc func handleMapTap(_ sender: UITapGestureRecognizer) {
      guard let mapView = self.mapView ?? sender.view as? MapView else {
        print("⚠️ [MAP TAP] MapView not available for tap")
        return
      }
      
      let point = sender.location(in: mapView)
      
      // Check if map is ready
      guard let mapboxMap = mapView.mapboxMap else {
        print("⚠️ [MAP TAP] MapboxMap not ready yet")
        return
      }
      
      // If in drawing mode, handle polygon drawing
      if isDrawingMode {
        let coordinate = mapboxMap.coordinate(for: point)
        addPolygonVertex(coordinate, on: mapView)
        print("✅ [POLYGON] Tap handled in drawing mode at \(coordinate)")
        return
      }
      
      // Not in drawing mode - check for campaign building/pin taps
      let box = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
      
      // Query for building polygons first (campaign-bldg-src)
      let buildingOptions = RenderedQueryOptions(layerIds: [bldgFillId], filter: nil)
      mapboxMap.queryRenderedFeatures(with: box, options: buildingOptions) { [weak self] result in
        guard let self = self else { return }
        
        switch result {
        case .success(let features):
          if let firstFeature = features.first {
            let feature = firstFeature.queriedFeature.feature
            if let addressId = self.extractAddressId(from: feature) {
              DispatchQueue.main.async {
                self.onAddressTapped?(addressId)
              }
              print("✅ [MAP TAP] Building tapped: \(addressId)")
              return
            }
          }
          
          // No building found, try pins
          let pinOptions = RenderedQueryOptions(layerIds: [self.layerCampaignPins], filter: nil)
          mapboxMap.queryRenderedFeatures(with: box, options: pinOptions) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let features):
              if let firstFeature = features.first {
                let feature = firstFeature.queriedFeature.feature
                if let addressId = self.extractAddressId(from: feature) {
                  DispatchQueue.main.async {
                    self.onAddressTapped?(addressId)
                  }
                  print("✅ [MAP TAP] Pin tapped: \(addressId)")
                  return
                }
              }
            case .failure(let error):
              print("⚠️ [MAP TAP] Error querying pins: \(error)")
            }
          }
          
        case .failure(let error):
          print("⚠️ [MAP TAP] Error querying buildings: \(error)")
        }
      }
    }
    
    /// Extract address_id from feature properties
    private func extractAddressId(from feature: Feature) -> String? {
      guard let properties = feature.properties else { return nil }
      
      // Try "address_id" first (primary key)
      if case let .string(addressId)? = properties["address_id"] {
        return addressId
      }
      
      // Try "id" as fallback
      if case let .string(id)? = properties["id"] {
        // Check if it looks like a UUID
        if UUID(uuidString: id) != nil {
          return id
        }
      }
      
      return nil
    }
    
    func addPolygonVertex(_ coordinate: CLLocationCoordinate2D, on mapView: MapView) {
      polygonVertices.append(coordinate)
      updatePolygonOverlay(on: mapView)
      print("📍 [POLYGON] Added vertex \(polygonVertices.count): \(coordinate)")
    }
    
    func updatePolygonOverlay(on mapView: MapView) {
      guard !polygonVertices.isEmpty else {
        clearPolygon(on: mapView)
        return
      }
      
      // Need at least 2 points to draw a line
      guard polygonVertices.count >= 2 else { return }
      
      // Create polygon from vertices (close it by adding first point at end)
      var coords = polygonVertices
      if coords.first != coords.last {
        coords.append(coords.first!)
      }
      
      // Convert to Mapbox Polygon
      let polygonCoords = coords.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
      let polygon = Polygon([polygonCoords])
      let feature = Feature(geometry: .polygon(polygon))
      
      guard let map = mapView.mapboxMap else { return }
      
      do {
        // Create or update source
        if map.allSourceIdentifiers.contains(where: { $0.id == drawPolygonSourceId }) {
          try map.updateGeoJSONSource(withId: drawPolygonSourceId, geoJSON: .feature(feature))
        } else {
          var source = GeoJSONSource(id: drawPolygonSourceId)
          source.data = .feature(feature)
          try map.addSource(source)
          
          // Add fill layer (semi-transparent red)
          var fillLayer = FillLayer(id: drawPolygonFillId, source: drawPolygonSourceId)
          fillLayer.fillColor = .constant(StyleColor(.red))
          fillLayer.fillOpacity = .constant(0.2) // 20% opacity
          fillLayer.fillOutlineColor = .constant(StyleColor(.clear))
          try map.addLayer(fillLayer)
          
          // Add line layer (red outline)
          var lineLayer = LineLayer(id: drawPolygonLineId, source: drawPolygonSourceId)
          lineLayer.lineColor = .constant(StyleColor(.red))
          lineLayer.lineWidth = .constant(2.0)
          lineLayer.lineOpacity = .constant(1.0)
          lineLayer.lineJoin = .constant(.round)
          lineLayer.lineCap = .constant(.round)
          try map.addLayer(lineLayer, layerPosition: .above(drawPolygonFillId))
        }
      } catch {
        print("⚠️ [POLYGON] Error updating polygon overlay: \(error)")
      }
    }
    
    func finalizePolygon(on mapView: MapView) {
      guard polygonVertices.count >= 3 else {
        print("⚠️ [POLYGON] Cannot finalize polygon with fewer than 3 points")
        clearPolygon(on: mapView)
        return
      }
      
      // Close polygon if not already closed
      var finalVertices = polygonVertices
      if finalVertices.first != finalVertices.last {
        finalVertices.append(finalVertices.first!)
      }
      
      // Call completion handler
      onPolygonComplete?(polygonVertices)
      
      // Clear drawing state
      clearPolygon(on: mapView)
    }
    
    func clearPolygon(on mapView: MapView) {
      polygonVertices.removeAll()
      
      guard let map = mapView.mapboxMap else { return }
      
      do {
        // Remove layers
        if map.allLayerIdentifiers.contains(where: { $0.id == drawPolygonFillId }) {
          try map.removeLayer(withId: drawPolygonFillId)
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == drawPolygonLineId }) {
          try map.removeLayer(withId: drawPolygonLineId)
        }
        
        // Remove source
        if map.allSourceIdentifiers.contains(where: { $0.id == drawPolygonSourceId }) {
          try map.removeSource(withId: drawPolygonSourceId)
        }
      } catch {
        print("⚠️ [POLYGON] Error clearing polygon: \(error)")
      }
    }
  }
}
