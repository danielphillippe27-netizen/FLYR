
// ============================================================
// FLYR PRO iOS - QUICK START IMPLEMENTATION
// Copy these files directly into your Xcode project
// ============================================================

// MARK: - File 1: Models.swift
// ============================================================

import Foundation
import CoreLocation

// Building data from S3 (via API)
struct BuildingFeature: Codable {
    let type: String
    let id: String
    let geometry: PolygonGeometry
    let properties: BuildingProperties
}

struct PolygonGeometry: Codable {
    let type: String
    let coordinates: [[[[Double]]]]
}

struct BuildingProperties: Codable {
    let gersId: String
    let heightM: Double
    let levels: Int?
    let addressText: String?
    let featureStatus: String
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case heightM = "height_m"
        case levels
        case addressText = "address_text"
        case featureStatus = "feature_status"
    }
}

// Address data from Supabase (via API)
struct AddressFeature: Codable {
    let type: String
    let geometry: PointGeometry
    let properties: AddressProperties
}

struct PointGeometry: Codable {
    let type: String
    let coordinates: [Double]  // [lon, lat]
}

struct AddressProperties: Codable {
    let id: String
    let formatted: String
    let visited: Bool
    let houseBearing: Double?
    let roadBearing: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, formatted, visited
        case houseBearing = "house_bearing"
        case roadBearing = "road_bearing"
    }
}

enum MapDisplayMode {
    case buildings, addresses, both
}

// MARK: - File 2: MapService.swift
// ============================================================

import Foundation

class CampaignMapService {
    static let shared = CampaignMapService()
    private let baseURL = "https://flyrpro.app/api"
    
    func fetchBuildings(campaignId: String) async throws -> [BuildingFeature] {
        let url = URL(string: "\(baseURL)/campaigns/\(campaignId)/buildings")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Try FeatureCollection first
        if let response = try? JSONDecoder().decode(BuildingsResponse.self, from: data) {
            return response.features
        }
        // Fallback to array
        return try JSONDecoder().decode([BuildingFeature].self, from: data)
    }
    
    func fetchAddresses(campaignId: String) async throws -> [AddressFeature] {
        let url = URL(string: "\(baseURL)/campaigns/\(campaignId)/addresses")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([AddressFeature].self, from: data)
    }
}

struct BuildingsResponse: Codable {
    let type: String
    let features: [BuildingFeature]
}

// MARK: - File 3: MapViewController.swift
// ============================================================

import UIKit
import MapboxMaps

class CampaignMapViewController: UIViewController {
    
    // UI
    var mapView: MapView!
    let modeToggle = UISegmentedControl(items: ["Buildings", "Addresses", "Both"])
    let loadingIndicator = UIActivityIndicatorView(style: .large)
    
    // Data
    var campaignId: String!
    var currentMode: MapDisplayMode = .buildings
    var buildings: [BuildingFeature] = []
    var addresses: [AddressFeature] = []
    
    // Map IDs
    let buildingSourceId = "buildings-source"
    let buildingLayerId = "buildings-3d"
    let addressSourceId = "addresses-source"
    let addressLayerId = "address-pins"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMap()
        loadData()
    }
    
    func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Toggle
        modeToggle.selectedSegmentIndex = 0
        modeToggle.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeToggle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeToggle)
        
        // Loading
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            modeToggle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            modeToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            modeToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    func setupMap() {
        let options = MapInitOptions(cameraOptions: CameraOptions(zoom: 15, pitch: 45))
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(mapView, at: 0)
        
        // 3D light
        var light = Light()
        light.anchor = .map
        light.position = .constant([1.5, 90, 80])
        light.intensity = .constant(0.5)
        try? mapView.mapboxMap.style.setLight(light)
    }
    
    func loadData() {
        loadingIndicator.startAnimating()
        
        Task {
            do {
                async let b = CampaignMapService.shared.fetchBuildings(campaignId: campaignId)
                async let a = CampaignMapService.shared.fetchAddresses(campaignId: campaignId)
                buildings = try await b
                addresses = try await a
                
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    self.updateMap()
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    print("Error: \(error)")
                }
            }
        }
    }
    
    @objc func modeChanged() {
        switch modeToggle.selectedSegmentIndex {
        case 0: currentMode = .buildings
        case 1: currentMode = .addresses
        default: currentMode = .both
        }
        updateMap()
    }
    
    func updateMap() {
        // Clear all
        try? mapView.mapboxMap.style.removeLayer(withId: buildingLayerId)
        try? mapView.mapboxMap.style.removeSource(withId: buildingSourceId)
        try? mapView.mapboxMap.style.removeLayer(withId: addressLayerId)
        try? mapView.mapboxMap.style.removeSource(withId: addressSourceId)
        
        // Add based on mode
        if currentMode == .buildings || currentMode == .both {
            addBuildings()
        }
        if currentMode == .addresses || currentMode == .both {
            addAddresses()
        }
    }
    
    func addBuildings() {
        guard !buildings.isEmpty else { return }
        
        var features: [Feature] = []
        for b in buildings {
            // Convert coordinates
            guard let ring = b.geometry.coordinates.first?.first else { continue }
            var coords: [CLLocationCoordinate2D] = []
            for p in ring {
                coords.append(CLLocationCoordinate2D(latitude: p[1], longitude: p[0]))
            }
            
            var props = JSONObject()
            props["gers_id"] = .string(b.properties.gersId)
            props["height_m"] = .number(b.properties.heightM)
            props["scans_total"] = .number(0)
            props["status"] = .string("not_visited")
            
            features.append(Feature(
                geometry: .polygon(Polygon([Ring(coordinates: coords)])),
                properties: props
            ))
        }
        
        var source = GeoJSONSource()
        source.data = .featureCollection(FeatureCollection(features: features))
        source.promoteId = .string("gers_id")
        
        do {
            try mapView.mapboxMap.style.addSource(source, id: buildingSourceId)
            
            var layer = FillExtrusionLayer(id: buildingLayerId)
            layer.source = buildingSourceId
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height_m" })
            layer.fillExtrusionBase = .constant(0)
            layer.fillExtrusionOpacity = .constant(0.85)
            layer.fillExtrusionColor = .expression(colorExpr())
            
            try mapView.mapboxMap.style.addLayer(layer)
        } catch {
            print("Building error: \(error)")
        }
    }
    
    func addAddresses() {
        guard !addresses.isEmpty else { return }
        
        var features: [Feature] = []
        for a in addresses {
            let coord = CLLocationCoordinate2D(
                latitude: a.geometry.coordinates[1],
                longitude: a.geometry.coordinates[0]
            )
            
            var props = JSONObject()
            props["id"] = .string(a.properties.id)
            props["formatted"] = .string(a.properties.formatted)
            props["visited"] = .boolean(a.properties.visited)
            props["house_bearing"] = a.properties.houseBearing.map { .number($0) } ?? .null
            
            features.append(Feature(geometry: .point(Point(coord)), properties: props))
        }
        
        var source = GeoJSONSource()
        source.data = .featureCollection(FeatureCollection(features: features))
        
        do {
            try mapView.mapboxMap.style.addSource(source, id: addressSourceId)
            
            var layer = CircleLayer(id: addressLayerId)
            layer.source = addressSourceId
            layer.circleRadius = .constant(8)
            layer.circleColor = .expression(
                Exp(.switchCase) {
                    Exp(.eq) { Exp(.get) { "visited" }; true }
                    UIColor.green
                    UIColor.red
                }
            )
            layer.circleStrokeWidth = .constant(2)
            layer.circleStrokeColor = .constant(.white)
            
            try mapView.mapboxMap.style.addLayer(layer)
        } catch {
            print("Address error: \(error)")
        }
    }
    
    func colorExpr() -> Exp {
        Exp(.switchCase) {
            Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
            UIColor(hex: "#facc15")  // Yellow
            Exp(.eq) { Exp(.get) { "status" }; "hot" }
            UIColor(hex: "#3b82f6")  // Blue
            Exp(.eq) { Exp(.get) { "status" }; "visited" }
            UIColor(hex: "#22c55e")  // Green
            UIColor(hex: "#ef4444")  // Red
        }
    }
}

// MARK: - File 4: Extensions.swift
// ============================================================

import UIKit

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}

// MARK: - Usage
// ============================================================
//
// let vc = CampaignMapViewController()
// vc.campaignId = "3204e847-1124-4817-8262-856f29871b7f"
// navigationController?.pushViewController(vc, animated: true)
//
// ============================================================
