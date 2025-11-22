import Foundation
import MapboxMaps
import CoreLocation
import UIKit

/// Manages map markers for campaigns and farms
@MainActor
final class MapMarkersManager {
    static let shared = MapMarkersManager()
    
    private let campaignSourceId = "campaign-markers-source"
    private let campaignLayerId = "campaign-markers-layer"
    private let farmSourceId = "farm-markers-source"
    private let farmLayerId = "farm-markers-layer"
    
    private init() {}
    
    /// Add campaign markers to the map
    func addCampaignMarkers(campaigns: [CampaignMarker], to mapView: MapView) {
        guard let map = mapView.mapboxMap else { return }
        
        // Wait for map to load
        if !map.isStyleLoaded {
            map.onMapLoaded.observeNext { [weak self] _ in
                Task { @MainActor in
                    await self?.addCampaignMarkersInternal(campaigns: campaigns, to: mapView)
                }
            }
            return
        }
        
        Task {
            await addCampaignMarkersInternal(campaigns: campaigns, to: mapView)
        }
    }
    
    private func addCampaignMarkersInternal(campaigns: [CampaignMarker], to mapView: MapView) async {
        guard let map = mapView.mapboxMap else { return }
        
        // Create features from campaign markers
        let features = campaigns.map { marker -> Feature in
            var feature = Feature(geometry: .point(Point(marker.coordinate)))
            feature.properties = [
                "id": .string(marker.id.uuidString),
                "name": .string(marker.name),
                "type": .string("campaign")
            ]
            return feature
        }
        
        let featureCollection = FeatureCollection(features: features)
        
        do {
            // Remove ALL existing layers that use this source before removing the source
            let campaignLayerIds = [campaignLayerId, "\(campaignLayerId)-inner", "\(campaignLayerId)-text"]
            for layerId in campaignLayerIds {
                if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                    try map.removeLayer(withId: layerId)
                }
            }
            // Now safe to remove the source
            if map.allSourceIdentifiers.contains(where: { $0.id == campaignSourceId }) {
                try map.removeSource(withId: campaignSourceId)
            }
            
            // Add source
            var source = GeoJSONSource(id: campaignSourceId)
            source.data = .featureCollection(featureCollection)
            try map.addSource(source)
            
            // Add circle layer for target-like appearance (outer circle)
            var circleLayer = CircleLayer(id: campaignLayerId, source: campaignSourceId)
            circleLayer.circleRadius = .constant(8)
            circleLayer.circleColor = .constant(StyleColor(.systemRed))
            circleLayer.circleStrokeColor = .constant(StyleColor(.white))
            circleLayer.circleStrokeWidth = .constant(2)
            circleLayer.circleOpacity = .constant(0.8)
            try map.addLayer(circleLayer)
            
            // Add inner circle for target appearance
            let innerLayerId = "\(campaignLayerId)-inner"
            var innerLayer = CircleLayer(id: innerLayerId, source: campaignSourceId)
            innerLayer.circleRadius = .constant(4)
            innerLayer.circleColor = .constant(StyleColor(.systemRed))
            innerLayer.circleOpacity = .constant(1.0)
            try map.addLayer(innerLayer, layerPosition: .above(campaignLayerId))
            
            // Add text label layer
            let textLayerId = "\(campaignLayerId)-text"
            var textLayer = SymbolLayer(id: textLayerId, source: campaignSourceId)
            textLayer.textField = .expression(Exp(.get) { "name" })
            textLayer.textSize = .constant(12)
            textLayer.textColor = .constant(StyleColor(.label))
            textLayer.textHaloColor = .constant(StyleColor(.systemBackground))
            textLayer.textHaloWidth = .constant(1)
            textLayer.textAnchor = .constant(.top)
            textLayer.textOffset = .constant([0, 2])
            textLayer.textOptional = .constant(true)
            try map.addLayer(textLayer, layerPosition: .above(innerLayerId))
            print("✅ [MapMarkers] Added \(campaigns.count) campaign markers")
        } catch {
            print("❌ [MapMarkers] Failed to add campaign markers: \(error)")
        }
    }
    
    /// Add farm markers to the map
    func addFarmMarkers(farms: [FarmMarker], to mapView: MapView) {
        guard let map = mapView.mapboxMap else { return }
        
        // Wait for map to load
        if !map.isStyleLoaded {
            map.onMapLoaded.observeNext { [weak self] _ in
                Task { @MainActor in
                    await self?.addFarmMarkersInternal(farms: farms, to: mapView)
                }
            }
            return
        }
        
        Task {
            await addFarmMarkersInternal(farms: farms, to: mapView)
        }
    }
    
    private func addFarmMarkersInternal(farms: [FarmMarker], to mapView: MapView) async {
        guard let map = mapView.mapboxMap else { return }
        
        // Create features from farm markers
        let features = farms.map { marker -> Feature in
            var feature = Feature(geometry: .point(Point(marker.coordinate)))
            feature.properties = [
                "id": .string(marker.id.uuidString),
                "name": .string(marker.name),
                "type": .string("farm")
            ]
            return feature
        }
        
        let featureCollection = FeatureCollection(features: features)
        
        do {
            // Remove ALL existing layers that use this source before removing the source
            let farmLayerIds = [farmLayerId, "\(farmLayerId)-inner", "\(farmLayerId)-text"]
            for layerId in farmLayerIds {
                if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                    try map.removeLayer(withId: layerId)
                }
            }
            // Now safe to remove the source
            if map.allSourceIdentifiers.contains(where: { $0.id == farmSourceId }) {
                try map.removeSource(withId: farmSourceId)
            }
            
            // Add source
            var source = GeoJSONSource(id: farmSourceId)
            source.data = .featureCollection(featureCollection)
            try map.addSource(source)
            
            // Add circle layer for target-like appearance (outer circle)
            var circleLayer = CircleLayer(id: farmLayerId, source: farmSourceId)
            circleLayer.circleRadius = .constant(8)
            circleLayer.circleColor = .constant(StyleColor(.systemBlue))
            circleLayer.circleStrokeColor = .constant(StyleColor(.white))
            circleLayer.circleStrokeWidth = .constant(2)
            circleLayer.circleOpacity = .constant(0.8)
            try map.addLayer(circleLayer)
            
            // Add inner circle for target appearance
            let innerLayerId = "\(farmLayerId)-inner"
            var innerLayer = CircleLayer(id: innerLayerId, source: farmSourceId)
            innerLayer.circleRadius = .constant(4)
            innerLayer.circleColor = .constant(StyleColor(.systemBlue))
            innerLayer.circleOpacity = .constant(1.0)
            try map.addLayer(innerLayer, layerPosition: .above(farmLayerId))
            
            // Add text label layer
            let textLayerId = "\(farmLayerId)-text"
            var textLayer = SymbolLayer(id: textLayerId, source: farmSourceId)
            textLayer.textField = .expression(Exp(.get) { "name" })
            textLayer.textSize = .constant(12)
            textLayer.textColor = .constant(StyleColor(.label))
            textLayer.textHaloColor = .constant(StyleColor(.systemBackground))
            textLayer.textHaloWidth = .constant(1)
            textLayer.textAnchor = .constant(.top)
            textLayer.textOffset = .constant([0, 2])
            textLayer.textOptional = .constant(true)
            try map.addLayer(textLayer, layerPosition: .above(innerLayerId))
            print("✅ [MapMarkers] Added \(farms.count) farm markers")
        } catch {
            print("❌ [MapMarkers] Failed to add farm markers: \(error)")
        }
    }
    
    /// Remove all markers from the map
    func removeAllMarkers(from mapView: MapView) {
        guard let map = mapView.mapboxMap else { return }
        
        // Remove campaign marker layers
        let campaignLayerIds = [campaignLayerId, "\(campaignLayerId)-inner", "\(campaignLayerId)-text"]
        for layerId in campaignLayerIds {
            if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                try? map.removeLayer(withId: layerId)
            }
        }
        if map.allSourceIdentifiers.contains(where: { $0.id == campaignSourceId }) {
            try? map.removeSource(withId: campaignSourceId)
        }
        
        // Remove farm marker layers
        let farmLayerIds = [farmLayerId, "\(farmLayerId)-inner", "\(farmLayerId)-text"]
        for layerId in farmLayerIds {
            if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                try? map.removeLayer(withId: layerId)
            }
        }
        if map.allSourceIdentifiers.contains(where: { $0.id == farmSourceId }) {
            try? map.removeSource(withId: farmSourceId)
        }
        
        print("✅ [MapMarkers] Removed all markers")
    }
}

// MARK: - Marker Models

struct CampaignMarker {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct FarmMarker {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Helper Extensions

extension CampaignMarker {
    /// Calculate center coordinate from campaign addresses
    static func fromCampaign(_ campaign: CampaignListItem, addresses: [CampaignAddressRow]) -> CampaignMarker? {
        guard !addresses.isEmpty else { return nil }
        
        // Calculate average of all address coordinates
        let sumLat = addresses.reduce(0.0) { $0 + $1.lat }
        let sumLon = addresses.reduce(0.0) { $0 + $1.lon }
        let count = Double(addresses.count)
        
        let center = CLLocationCoordinate2D(
            latitude: sumLat / count,
            longitude: sumLon / count
        )
        
        return CampaignMarker(
            id: campaign.id,
            name: campaign.name,
            coordinate: center
        )
    }
}

extension FarmMarker {
    /// Calculate center coordinate from farm polygon
    static func fromFarm(_ farm: Farm) -> FarmMarker? {
        guard let coords = farm.polygonCoordinates,
              !coords.isEmpty else {
            return nil
        }
        
        // Calculate centroid
        let sumLat = coords.reduce(0.0) { $0 + $1.latitude }
        let sumLon = coords.reduce(0.0) { $0 + $1.longitude }
        let count = Double(coords.count)
        
        let center = CLLocationCoordinate2D(
            latitude: sumLat / count,
            longitude: sumLon / count
        )
        
        return FarmMarker(
            id: farm.id,
            name: farm.name,
            coordinate: center
        )
    }
    
    /// Calculate center coordinate from farm list item (requires fetching full farm)
    static func fromFarmListItem(_ farmItem: FarmListItem, farm: Farm) -> FarmMarker? {
        return fromFarm(farm)
    }
}

