import UIKit
import MapboxMaps
import Supabase

/// Map view controller with building-address linking support
final class BuildingLinkMapViewController: UIViewController {
    
    // MARK: - Properties
    
    var mapView: MapView!
    var campaignId: String!
    
    // Data
    private var campaignData: CampaignBuildingData?
    private var realtimeChannel: RealtimeChannel?
    
    // UI
    private var popupView: BuildingPopupView?
    private var loadingIndicator: UIActivityIndicatorView?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        setupLoadingIndicator()
        loadCampaignData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Cleanup realtime subscription
        Task {
            await realtimeChannel?.unsubscribe()
        }
    }
    
    // MARK: - Setup
    
    private func setupMap() {
        let options = MapInitOptions(
            cameraOptions: CameraOptions(zoom: 15)
        )
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        
        // Add tap gesture for building selection
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
    }
    
    private func setupLoadingIndicator() {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.center = view.center
        indicator.hidesWhenStopped = true
        view.addSubview(indicator)
        loadingIndicator = indicator
    }
    
    // MARK: - Data Loading
    
    private func loadCampaignData() {
        loadingIndicator?.startAnimating()
        
        Task {
            do {
                let data = try await BuildingLinkService.shared.loadCampaignData(campaignId: campaignId)
                self.campaignData = data
                
                await MainActor.run {
                    self.loadingIndicator?.stopAnimating()
                    self.renderBuildings()
                    self.setupRealtimeSubscription()
                    self.centerMapOnBuildings()
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator?.stopAnimating()
                    self.showError(error)
                }
            }
        }
    }
    
    // MARK: - Render Buildings
    
    private func renderBuildings() {
        guard let data = campaignData else { return }
        
        var features: [Feature] = []
        
        for buildingData in data.buildings {
            let building = buildingData.building
            let gersId = building.id ?? ""

            guard let geometry = convertToMapboxGeometry(building.geometry) else { continue }

            let stats = data.stats[gersId]
            var properties: [String: JSONValue] = [:]
            properties["gers_id"] = .string(gersId)
            let height = building.properties.heightM ?? building.properties.height
            properties["height_m"] = .number(height)
            properties["address_text"] = .string(building.properties.addressText ?? "")
            properties["feature_status"] = .string(building.properties.featureStatus ?? "unknown")
            properties["scans_total"] = .number(Double(stats?.scansTotal ?? building.properties.scansTotal))
            properties["status"] = .string(stats?.status ?? building.properties.status)
            properties["is_linked"] = .boolean(buildingData.link != nil)

            var feature = Feature(geometry: geometry)
            feature.properties = properties
            feature.identifier = .string(gersId)
            features.append(feature)
        }

        var source = GeoJSONSource(id: "campaign-buildings")
        source.data = .featureCollection(FeatureCollection(features: features))
        source.promoteId = .string("gers_id")

        do {
            if mapView.mapboxMap.style.sourceExists(withId: "campaign-buildings") {
                try mapView.mapboxMap.style.removeSource(withId: "campaign-buildings")
            }
            try mapView.mapboxMap.style.addSource(source)
            addBuildingLayer()
            
            print("✅ [BuildingLinkMap] Rendered \(features.count) buildings")
            
        } catch {
            print("❌ [BuildingLinkMap] Error rendering buildings: \(error)")
        }
    }
    
    private func addBuildingLayer() {
        var layer = FillExtrusionLayer(id: "buildings-3d", source: "campaign-buildings")
        layer.fillExtrusionHeight = .expression(Exp(.get) { "height_m" })
        layer.fillExtrusionBase = .constant(0)
        layer.fillExtrusionOpacity = .constant(0.85)
        layer.fillExtrusionColor = .expression(colorExpression())
        
        do {
            try mapView.mapboxMap.style.addLayer(layer)
        } catch {
            print("❌ [BuildingLinkMap] Error adding layer: \(error)")
        }
    }
    
    private func colorExpression() -> Exp {
        Exp(.switchCase) {
            // Priority 1: QR Scanned (purple)
            Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
            UIColor(hex: "#8b5cf6")!
            
            // Priority 2: Hot/Conversation (BLUE)
            Exp(.eq) { Exp(.get) { "status" }; "hot" }
            UIColor(hex: "#3b82f6")!
            
            // Priority 3: Visited/Touched (GREEN)
            Exp(.eq) { Exp(.get) { "status" }; "visited" }
            UIColor(hex: "#22c55e")!
            
            // Default: Not visited (RED)
            UIColor(hex: "#ef4444")!
        }
    }
    
    // MARK: - Map Interaction
    
    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: mapView)
        let options = RenderedQueryOptions(layerIds: ["buildings-3d"], filter: nil)
        mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let queriedFeatures):
                guard let first = queriedFeatures.first,
                      let props = first.queriedFeature.feature.properties,
                      case .string(let gersId) = props["gers_id"] else {
                    return
                }
                DispatchQueue.main.async {
                    self.showBuildingPopup(gersId: gersId)
                }
            case .failure(let error):
                print("❌ [BuildingLinkMap] Query error: \(error)")
            }
        }
    }
    
    private func showBuildingPopup(gersId: String) {
        guard let buildingData = campaignData?.buildings.first(where: { ($0.building.id ?? "") == gersId }) else {
            return
        }
        
        // Remove existing popup
        popupView?.removeFromSuperview()
        
        // Create and show popup
        let popup = BuildingPopupView(frame: view.bounds)
        popup.configure(
            with: buildingData,
            onClose: { [weak self] in
                self?.popupView?.removeFromSuperview()
                self?.popupView = nil
            },
            onAction: { [weak self] in
                self?.handleBuildingAction(buildingData: buildingData)
            }
        )
        
        view.addSubview(popup)
        popupView = popup
    }
    
    private func handleBuildingAction(buildingData: BuildingWithAddress) {
        guard let address = buildingData.address else { return }
        let addressText = address.address
        let isVisited = buildingData.stats?.status == "visited"
        if isVisited {
            print("📋 Show details for: \(addressText)")
        } else {
            print("✅ Mark visited: \(addressText)")
            // TODO: Call API to update status
        }
    }
    
    // MARK: - Real-time Updates
    
    private func setupRealtimeSubscription() {
        Task {
            do {
                realtimeChannel = try await BuildingLinkService.shared.subscribeToBuildingStats(
                    campaignId: campaignId
                ) { [weak self] stats in
                    self?.handleRealtimeUpdate(stats: stats)
                }
            } catch {
                print("❌ [BuildingLinkMap] Failed to subscribe: \(error)")
            }
        }
    }
    
    private func handleRealtimeUpdate(stats: BuildingStats) {
        DispatchQueue.main.async { [weak self] in
            self?.mapView.mapboxMap.setFeatureState(
                sourceId: "campaign-buildings",
                featureId: stats.gersId,
                state: [
                    "scans_total": stats.scansTotal,
                    "status": stats.status
                ]
            ) { _ in }
            print("🔄 [BuildingLinkMap] Updated building \(stats.gersId): \(stats.status), scans: \(stats.scansTotal)")
        }
    }
    
    // MARK: - Helpers
    
    private func centerMapOnBuildings() {
        guard let firstBuilding = campaignData?.buildings.first else { return }
        
        // Get centroid from first building
        if let coordinate = extractCoordinate(from: firstBuilding.building.geometry) {
            let camera = CameraOptions(
                center: coordinate,
                zoom: 16
            )
            mapView.mapboxMap.setCamera(to: camera)
        }
    }
    
    private func convertToMapboxGeometry(_ geometry: MapFeatureGeoJSONGeometry) -> MapboxMaps.Geometry? {
        if let polygon = geometry.asPolygon {
            let polygonCoords = polygon.map { ring in
                ring.map { coord in
                    LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }
            return .polygon(Polygon(polygonCoords))
        }
        if let multi = geometry.asMultiPolygon {
            let multiCoords = multi.map { polygon in
                polygon.map { ring in
                    ring.map { coord in
                        LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    }
                }
            }
            return .multiPolygon(MultiPolygon(multiCoords))
        }
        return nil
    }

    private func extractCoordinate(from geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        if let polygon = geometry.asPolygon,
           let firstRing = polygon.first,
           let firstPoint = firstRing.first,
           firstPoint.count >= 2 {
            return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
        }
        if let multi = geometry.asMultiPolygon,
           let firstPoly = multi.first,
           let firstRing = firstPoly.first,
           let firstPoint = firstRing.first,
           firstPoint.count >= 2 {
            return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
        }
        return nil
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: "Failed to load campaign data: \(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.loadCampaignData()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
