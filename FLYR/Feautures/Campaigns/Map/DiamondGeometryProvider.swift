import Foundation
@_spi(Experimental) import MapboxMaps
import Supabase
import UIKit

@MainActor
protocol DiamondGeometryProvider {
    func installGeometry(
        for campaignId: String,
        manifest: DiamondManifest,
        on mapView: MapView,
        territoryBoundary: GeoJSONObject?
    ) async throws

    func applyTerritoryBoundary(_ boundary: GeoJSONObject?, on mapView: MapView) throws

    func removeGeometry(from mapView: MapView) throws
}

@MainActor
final class VectorTileDiamondGeometryProvider: DiamondGeometryProvider {
    static let buildingSourceId = "diamond-buildings"
    static let sourceId = buildingSourceId
    static let addressSourceId = "diamond-addresses"
    static let parcelSourceId = "diamond-parcels"
    static let parcelFillLayerId = "diamond-parcels-fill"
    static let parcelLineLayerId = "diamond-parcels-line"
    static let buildingFillLayerId = "diamond-buildings-fill"
    static let buildingLineLayerId = "diamond-buildings-line"
    static let buildingLeadGlowLayerId = "diamond-buildings-lead-glow"
    static let buildingAddressNumberLayerId = "diamond-buildings-address-numbers"
    static let addressCircleLayerId = "diamond-addresses-circles"
    static let selectedAddressCircleLayerId = "diamond-addresses-selected"
    static let addressNumberLayerId = "diamond-addresses-numbers"
    static let parcelOverviewMinZoom: Double = 0.0
    static let parcelOverviewMaxZoom: Double = 24.0
    static let addressLayerMinZoom: Double = 11.8
    static let addressNumberLayerMinZoom: Double = 17.0
    static var addressNumberZoomOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            Self.addressNumberLayerMinZoom
            0.0
            17.25
            0.28
            17.5
            0.62
            17.8
            0.9
            18.1
            1.0
        }
    }

    static var addressNumberOpacityExpression: Exp {
        addressNumberZoomOpacityExpression
    }

    static func linkedAddressNumberOpacityExpression(linkedExpression: Exp, isAddressMode: Bool = false) -> Exp {
        if isAddressMode {
            return Self.addressNumberZoomOpacityExpression
        }
        return Exp(.switchCase) {
            linkedExpression
            Self.addressNumberZoomOpacityExpression
            0.0
        }
    }

    static var linkedBuildingNumberExpression: Exp {
        Exp(.any) {
            Exp(.eq) {
                Exp(.coalesce) {
                    Exp(.featureState) { "is_linked" }
                    Exp(.get) { "is_linked" }
                    false
                }
                true
            }
            linkedFeatureStatusExpression
            Exp(.gt) {
                Exp(.toNumber) {
                    Exp(.coalesce) {
                        Exp(.get) { "linked_address_count" }
                        Exp(.get) { "address_count" }
                        0
                    }
                }
                0
            }
        }
    }

    static var linkedAddressNumberExpression: Exp {
        Exp(.any) {
            Exp(.eq) {
                Exp(.coalesce) {
                    Exp(.featureState) { "is_linked" }
                    Exp(.get) { "is_linked" }
                    false
                }
                true
            }
            Exp(.neq) {
                Exp(.coalesce) {
                    Exp(.get) { "building_gers_id" }
                    Exp(.get) { "linked_building_id" }
                    ""
                }
                ""
            }
            linkedFeatureStatusExpression
            Exp(.gt) {
                Exp(.toNumber) {
                    Exp(.coalesce) {
                        Exp(.get) { "linked_address_count" }
                        Exp(.get) { "address_count" }
                        0
                    }
                }
                0
            }
        }
    }

    private static var linkedFeatureStatusExpression: Exp {
        Exp(.any) {
            Exp(.eq) {
                Exp(.coalesce) {
                    Exp(.get) { "feature_status" }
                    ""
                }
                "linked"
            }
            Exp(.eq) {
                Exp(.coalesce) {
                    Exp(.get) { "feature_status" }
                    ""
                }
                "matched"
            }
        }
    }

    private let buildingSourceId = VectorTileDiamondGeometryProvider.buildingSourceId
    private let addressSourceId = VectorTileDiamondGeometryProvider.addressSourceId
    private let parcelSourceId = VectorTileDiamondGeometryProvider.parcelSourceId
    private let parcelFillLayerId = VectorTileDiamondGeometryProvider.parcelFillLayerId
    private let parcelLineLayerId = VectorTileDiamondGeometryProvider.parcelLineLayerId
    private let buildingFillLayerId = VectorTileDiamondGeometryProvider.buildingFillLayerId
    private let buildingLineLayerId = VectorTileDiamondGeometryProvider.buildingLineLayerId
    private let buildingLeadGlowLayerId = VectorTileDiamondGeometryProvider.buildingLeadGlowLayerId
    private let buildingAddressNumberLayerId = VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId
    private let addressCircleLayerId = VectorTileDiamondGeometryProvider.addressCircleLayerId
    private let selectedAddressCircleLayerId = VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId
    private let addressNumberLayerId = VectorTileDiamondGeometryProvider.addressNumberLayerId
    private let parcelOverviewMinZoom = VectorTileDiamondGeometryProvider.parcelOverviewMinZoom
    private let parcelOverviewMaxZoom = VectorTileDiamondGeometryProvider.parcelOverviewMaxZoom
    private let buildingCapHeightMeters = 1.2
    private let addressLayerMinZoom = VectorTileDiamondGeometryProvider.addressLayerMinZoom
    private let addressCylinderHeightMeters = 3.0
    private let addressLabelCapClearanceMeters = 0.05
    private let selectedBuildingHeightScale = 1.0
    private var territoryBoundary: GeoJSONObject?
    private var currentAddressUsesCirclePolygons = false

    func installGeometry(
        for campaignId: String,
        manifest: DiamondManifest,
        on mapView: MapView,
        territoryBoundary: GeoJSONObject?
    ) async throws {
        guard manifest.isPMTilesGeometryProvider else {
            throw DiamondGeometryProviderError.unsupportedManifest
        }
        let rawTileTemplate = nonEmpty(manifest.vectorTileUrlTemplate)
        let buildingLayer = nonEmpty(manifest.sourceLayers?.buildings)
        let addressCircleLayer = nonEmpty(manifest.sourceLayers?.addressCircles)
        let addressPointLayer = nonEmpty(manifest.addressSourceLayer) ?? nonEmpty(manifest.sourceLayers?.addresses)
        let addressLayer = addressCircleLayer ?? addressPointLayer
        let rawAddressTileTemplate = nonEmpty(manifest.addressVectorTileUrlTemplate)
        let parcelLayer = nonEmpty(manifest.parcelSourceLayer) ?? nonEmpty(manifest.sourceLayers?.parcels)
        let rawParcelTileTemplate = nonEmpty(manifest.parcelVectorTileUrlTemplate)
        let canRenderBuildings = rawTileTemplate != nil && buildingLayer != nil
        let canRenderAddresses = rawAddressTileTemplate != nil && addressLayer != nil
        let canRenderParcels = rawParcelTileTemplate != nil && parcelLayer != nil
        guard canRenderBuildings || canRenderAddresses || canRenderParcels else {
            throw DiamondGeometryProviderError.unsupportedManifest
        }

        guard let map = mapView.mapboxMap else {
            throw DiamondGeometryProviderError.mapUnavailable
        }

        self.territoryBoundary = territoryBoundary
        try removeExistingDiamondLayers(from: map)

        if let rawTileTemplate, let buildingLayer {
            let buildingTileTemplate = await tileTemplateWithAccessToken(rawTileTemplate)
            try addVectorSource(
                map: map,
                sourceId: buildingSourceId,
                tileTemplate: buildingTileTemplate,
                minzoom: manifest.minzoom ?? 13,
                maxzoom: manifest.maxzoom ?? 18,
                bounds: manifest.bounds,
                promoteIds: [
                    buildingLayer: manifest.promoteIds?.buildings ?? "building_id"
                ]
            )
        }

        let parcelSourceForLayers: String
        if let rawParcelTileTemplate,
           let parcelLayer {
            let parcelTileTemplate = await tileTemplateWithAccessToken(rawParcelTileTemplate)
            try addVectorSource(
                map: map,
                sourceId: parcelSourceId,
                tileTemplate: parcelTileTemplate,
                minzoom: manifest.parcelMinzoom ?? 10,
                maxzoom: manifest.parcelMaxzoom ?? 16,
                bounds: expandedParcelSourceBounds(manifest.bounds),
                promoteIds: [
                    parcelLayer: manifest.joinKey ?? manifest.parcelPromoteId ?? manifest.promoteIds?.parcels ?? "parcel_id"
                ]
            )
            parcelSourceForLayers = parcelSourceId
        } else {
            parcelSourceForLayers = buildingSourceId
        }

        let addressSourceForLayers: String
        if let rawAddressTileTemplate,
           let addressLayer {
            let addressTileTemplate = await tileTemplateWithAccessToken(rawAddressTileTemplate)
            try addVectorSource(
                map: map,
                sourceId: addressSourceId,
                tileTemplate: addressTileTemplate,
                minzoom: manifest.addressMinzoom ?? 10,
                maxzoom: manifest.addressMaxzoom ?? 16,
                bounds: manifest.bounds,
                promoteIds: [
                    addressLayer: manifest.addressPromoteId ?? manifest.promoteIds?.addressCircles ?? manifest.promoteIds?.addresses ?? "address_id"
                ]
            )
            addressSourceForLayers = addressSourceId
        } else {
            addressSourceForLayers = buildingSourceId
        }

        if let parcelLayer, map.allSourceIdentifiers.contains(where: { $0.id == parcelSourceForLayers }) {
            try addParcelLayers(map: map, sourceId: parcelSourceForLayers, sourceLayer: parcelLayer)
        }
        if let buildingLayer, map.allSourceIdentifiers.contains(where: { $0.id == buildingSourceId }) {
            try addBuildingLayers(map: map, sourceId: buildingSourceId, sourceLayer: buildingLayer)
        }
        if let addressCircleLayer {
            try addAddressLayers(
                map: map,
                sourceId: addressSourceForLayers,
                sourceLayer: addressCircleLayer,
                usesCirclePolygons: true
            )
        } else if let addressPointLayer {
            try addAddressLayers(
                map: map,
                sourceId: addressSourceForLayers,
                sourceLayer: addressPointLayer,
                usesCirclePolygons: false
            )
        }
    }

    func applyTerritoryBoundary(_ boundary: GeoJSONObject?, on mapView: MapView) throws {
        guard let map = mapView.mapboxMap else {
            throw DiamondGeometryProviderError.mapUnavailable
        }

        territoryBoundary = boundary

        if map.allLayerIdentifiers.contains(where: { $0.id == buildingFillLayerId }) {
            try map.updateLayer(withId: buildingFillLayerId, type: FillExtrusionLayer.self) {
                $0.filter = diamondRenderableBuildingFilter()
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == buildingLineLayerId }) {
            try map.updateLayer(withId: buildingLineLayerId, type: LineLayer.self) {
                $0.filter = diamondRenderableBuildingFilter()
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == buildingAddressNumberLayerId }) {
            try map.updateLayer(withId: buildingAddressNumberLayerId, type: SymbolLayer.self) {
                $0.filter = singleAddressBuildingNumberFilter()
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == parcelFillLayerId }) {
            try map.updateLayer(withId: parcelFillLayerId, type: FillLayer.self) {
                $0.filter = scopedPolygonFilter()
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == parcelLineLayerId }) {
            try map.updateLayer(withId: parcelLineLayerId, type: LineLayer.self) {
                $0.filter = scopedPolygonFilter()
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == addressCircleLayerId }) {
            try? map.updateLayer(withId: addressCircleLayerId, type: FillExtrusionLayer.self) {
                $0.filter = addressGeometryFilter(usesCirclePolygons: true)
            }
            try? map.updateLayer(withId: addressCircleLayerId, type: CircleLayer.self) {
                $0.filter = addressGeometryFilter(usesCirclePolygons: false)
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == selectedAddressCircleLayerId }) {
            try? map.updateLayer(withId: selectedAddressCircleLayerId, type: FillExtrusionLayer.self) {
                $0.filter = addressGeometryFilter(usesCirclePolygons: true)
            }
            try? map.updateLayer(withId: selectedAddressCircleLayerId, type: CircleLayer.self) {
                $0.filter = addressGeometryFilter(usesCirclePolygons: false)
            }
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == addressNumberLayerId }) {
            try map.updateLayer(withId: addressNumberLayerId, type: SymbolLayer.self) {
                $0.filter = addressGeometryFilter(usesCirclePolygons: currentAddressUsesCirclePolygons)
            }
        }
    }

    func removeGeometry(from mapView: MapView) throws {
        guard let map = mapView.mapboxMap else {
            throw DiamondGeometryProviderError.mapUnavailable
        }
        try removeExistingDiamondLayers(from: map)
    }

    private func removeExistingDiamondLayers(from map: MapboxMap) throws {
        for layerId in [
            addressNumberLayerId,
            selectedAddressCircleLayerId,
            addressCircleLayerId,
            buildingAddressNumberLayerId,
            buildingLeadGlowLayerId,
            buildingLineLayerId,
            buildingFillLayerId,
            parcelLineLayerId,
            parcelFillLayerId
        ] {
            if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                try map.removeLayer(withId: layerId)
            }
        }
        for sourceId in [
            addressSourceId,
            parcelSourceId,
            buildingSourceId
        ] {
            if map.allSourceIdentifiers.contains(where: { $0.id == sourceId }) {
                try map.removeSource(withId: sourceId)
            }
        }
    }

    private func addVectorSource(
        map: MapboxMap,
        sourceId: String,
        tileTemplate: String,
        minzoom: Double,
        maxzoom: Double,
        bounds: [Double]?,
        promoteIds: [String: String]
    ) throws {
        var source = VectorSource(id: sourceId)
        source.tiles = [tileTemplate]
        source.minzoom = minzoom
        source.maxzoom = maxzoom
        source.bounds = bounds
        source.promoteId2 = .byLayer(
            promoteIds.reduce(into: [String: Value<String>]()) { result, entry in
                result[entry.key] = .constant(entry.value)
            }
        )

        try map.addSource(source)
    }

    private func expandedParcelSourceBounds(_ bounds: [Double]?) -> [Double]? {
        guard let bounds, bounds.count == 4 else { return bounds }
        let minLon = bounds[0]
        let minLat = bounds[1]
        let maxLon = bounds[2]
        let maxLat = bounds[3]
        guard [minLon, minLat, maxLon, maxLat].allSatisfy(\.isFinite),
              minLon < maxLon,
              minLat < maxLat else {
            return bounds
        }

        let lonPadding = max((maxLon - minLon) * 0.35, 0.002)
        let latPadding = max((maxLat - minLat) * 0.35, 0.002)
        return [
            max(-180.0, minLon - lonPadding),
            max(-85.05112878, minLat - latPadding),
            min(180.0, maxLon + lonPadding),
            min(85.05112878, maxLat + latPadding),
        ]
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func tileTemplateWithAccessToken(_ tileTemplate: String) async -> String {
        guard let session = try? await SupabaseManager.shared.client.auth.session,
              let encodedToken = session.accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return tileTemplate
        }
        let separator = tileTemplate.contains("?") ? "&" : "?"
        return "\(tileTemplate)\(separator)access_token=\(encodedToken)"
    }

    private func addBuildingLayers(map: MapboxMap, sourceId: String, sourceLayer: String) throws {
        let renderableFilter = diamondRenderableBuildingFilter()

        var fill = FillExtrusionLayer(id: buildingFillLayerId, source: sourceId)
        fill.sourceLayer = sourceLayer
        fill.fillExtrusionColor = .expression(
            statusFillColorExpression(
                defaultColor: MapStatusColor.untouched,
                selectedOverridesStatus: true
            )
        )
        fill.fillExtrusionHeight = .expression(
            selectedBuildingHeightExpression(
                base: MapLayerManager.buildingExtrusionHeightExpression
            )
        )
        fill.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
        fill.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
        fill.fillExtrusionBase = .expression(MapLayerManager.buildingExtrusionBaseExpression)
        fill.fillExtrusionOpacity = .constant(1.0)
        fill.fillExtrusionVerticalGradient = .constant(false)
        fill.minZoom = 12
        fill.filter = renderableFilter

        try map.addLayer(fill)

        var selectedGlow = LineLayer(id: buildingLineLayerId, source: sourceId)
        selectedGlow.sourceLayer = sourceLayer
        selectedGlow.lineColor = .constant(StyleColor(MapStatusColor.selectedHomeGlow))
        selectedGlow.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                12
                1.2
                16
                3.0
                20
                5.0
            }
        )
        selectedGlow.lineBlur = .constant(4.0)
        // Selection is shown by recoloring the extrusion; keep footprint outlines silent.
        selectedGlow.lineOpacity = .constant(0.0)
        selectedGlow.lineOpacityTransition = StyleTransition(duration: 0.2, delay: 0)
        selectedGlow.minZoom = 12
        selectedGlow.filter = renderableFilter

        try map.addLayer(selectedGlow, layerPosition: .above(buildingFillLayerId))

        try addBuildingAddressNumberLayer(map: map, sourceId: sourceId, sourceLayer: sourceLayer)

        // Lead/follow-up states are shown through the fill color. The line layer above is
        // selection-only, so normal homes do not carry an always-on footprint outline.
    }

    private func addBuildingAddressNumberLayer(map: MapboxMap, sourceId: String, sourceLayer: String) throws {
        var labels = SymbolLayer(id: buildingAddressNumberLayerId, source: sourceId)
        labels.sourceLayer = sourceLayer
        labels.textField = .expression(houseNumberLabelExpression())
        labels.textColor = .constant(StyleColor(.white))
        labels.textHaloColor = .constant(StyleColor(.black))
        labels.textHaloWidth = .constant(1.4)
        labels.textSize = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                17
                11.5
                20
                15
            }
        )
        labels.textAnchor = .constant(.center)
        labels.textJustify = .constant(.center)
        labels.textOffset = .constant([0, -0.35])
        labels.textPitchAlignment = .constant(.viewport)
        labels.textRotationAlignment = .constant(.viewport)
        labels.textVariableAnchor = .constant([.center])
        labels.textAllowOverlap = .constant(true)
        labels.textIgnorePlacement = .constant(true)
        labels.textOcclusionOpacity = .constant(1.0)
        labels.textOpacity = .expression(
            Self.linkedAddressNumberOpacityExpression(linkedExpression: Self.linkedBuildingNumberExpression)
        )
        labels.symbolPlacement = .constant(.point)
        labels.symbolZOrder = .constant(.auto)
        labels.symbolZElevate = .constant(true)
        labels.symbolElevationReference = .constant(.ground)
        labels.symbolZOffset = .expression(
            Exp(.sum) {
                MapLayerManager.buildingExtrusionHeightExpression
                addressLabelCapClearanceMeters
            }
        )
        labels.symbolSortKey = .constant(0)
        labels.minZoom = Self.addressNumberLayerMinZoom
        labels.filter = singleAddressBuildingNumberFilter()
        try map.addLayer(labels, layerPosition: .above(buildingLineLayerId))
    }

    private func houseNumberLabelExpression() -> Exp {
        Exp(.coalesce) {
            Exp(.get) { "house_number_label" }
            Exp(.get) { "house_number" }
            Exp(.get) { "street_number" }
            Exp(.get) { "number" }
            Exp(.get) { "address_number" }
            ""
        }
    }

    private func singleAddressBuildingNumberFilter() -> Exp {
        Exp(.all) {
            diamondRenderableBuildingFilter()
            Exp(.neq) {
                houseNumberLabelExpression()
                ""
            }
            Exp(.lte) {
                Exp(.toNumber) {
                    Exp(.coalesce) {
                        Exp(.get) { "linked_address_count" }
                        Exp(.get) { "address_count" }
                        Exp(.get) { "units_count" }
                        1
                    }
                }
                1
            }
        }
    }

    private func addParcelLayers(map: MapboxMap, sourceId: String, sourceLayer: String) throws {
        let parcelFilter = scopedPolygonFilter()

        var fill = FillLayer(id: parcelFillLayerId, source: sourceId)
        fill.sourceLayer = sourceLayer
        fill.fillColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.untouched))
        fill.fillOpacity = .expression(parcelOverviewFillOpacityExpression())
        fill.fillAntialias = .constant(false)
        fill.minZoom = parcelOverviewMinZoom
        fill.maxZoom = parcelOverviewMaxZoom
        fill.filter = parcelFilter
        try map.addLayer(fill)

        var line = LineLayer(id: parcelLineLayerId, source: sourceId)
        line.sourceLayer = sourceLayer
        line.lineColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.untouched))
        line.lineOpacity = .expression(parcelLineOpacityExpression())
        line.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                0.0
                Exp(.switchCase) {
                    isSelectedExpression()
                    1.4
                    0.42
                }
                12.0
                Exp(.switchCase) {
                    isSelectedExpression()
                    1.65
                    0.36
                }
                13.5
                Exp(.switchCase) {
                    isSelectedExpression()
                    1.82
                    0.38
                }
                15.0
                Exp(.switchCase) {
                    isSelectedExpression()
                    1.95
                    0.45
                }
                16.8
                Exp(.switchCase) {
                    isSelectedExpression()
                    2.16
                    0.85
                }
                19.0
                Exp(.switchCase) {
                    isSelectedExpression()
                    2.6
                    1.2
                }
                24.0
                Exp(.switchCase) {
                    isSelectedExpression()
                    3.2
                    1.3
                }
            }
        )
        line.minZoom = parcelOverviewMinZoom
        line.maxZoom = parcelOverviewMaxZoom
        line.filter = parcelFilter
        try map.addLayer(line, layerPosition: .above(parcelFillLayerId))
    }

    private func addAddressLayers(map: MapboxMap, sourceId: String, sourceLayer: String, usesCirclePolygons: Bool) throws {
        currentAddressUsesCirclePolygons = usesCirclePolygons
        let pointFilter = scopedPointFilter()
        let polygonFilter = scopedPolygonFilter()

        if usesCirclePolygons {
            var circles = FillExtrusionLayer(id: addressCircleLayerId, source: sourceId)
            circles.sourceLayer = sourceLayer
            circles.fillExtrusionColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.addressMarker))
            circles.fillExtrusionOpacity = .constant(0.98)
            circles.fillExtrusionHeight = .expression(addressCylinderHeightExpression())
            circles.fillExtrusionBase = .expression(addressCylinderBaseExpression())
            circles.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
            circles.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
            circles.fillExtrusionVerticalGradient = .constant(false)
            circles.minZoom = addressLayerMinZoom
            circles.filter = polygonFilter
            try map.addLayer(circles)

            var selected = FillExtrusionLayer(id: selectedAddressCircleLayerId, source: sourceId)
            selected.sourceLayer = sourceLayer
            selected.fillExtrusionColor = .constant(StyleColor(MapStatusColor.selectedHome))
            selected.fillExtrusionOpacity = .expression(
                Exp(.switchCase) {
                    isSelectedUnvisitedStatusExpression()
                    1.0
                    0.0
                }
            )
            selected.fillExtrusionHeight = .expression(addressCylinderHeightExpression())
            selected.fillExtrusionBase = .expression(addressCylinderBaseExpression())
            selected.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
            selected.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
            selected.fillExtrusionVerticalGradient = .constant(false)
            selected.minZoom = addressLayerMinZoom
            selected.filter = polygonFilter
            try map.addLayer(selected, layerPosition: .above(addressCircleLayerId))
        } else {
            var circles = CircleLayer(id: addressCircleLayerId, source: sourceId)
            circles.sourceLayer = sourceLayer
            circles.circleColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.addressMarker))
            circles.circleRadius = .expression(
                Exp(.interpolate) {
                    Exp(.linear)
                    Exp(.zoom)
                    11.8
                    2.5
                    13
                    3
                    14
                    4
                    17
                    7
                    20
                    10
                }
            )
            circles.circleOpacity = .constant(1.0)
            circles.circleStrokeColor = .constant(StyleColor(.white))
            circles.circleStrokeWidth = .constant(1.4)
            circles.minZoom = addressLayerMinZoom
            circles.filter = pointFilter
            try map.addLayer(circles)

            var selected = CircleLayer(id: selectedAddressCircleLayerId, source: sourceId)
            selected.sourceLayer = sourceLayer
            selected.circleColor = .constant(StyleColor(MapStatusColor.selectedHome))
            selected.circleRadius = .expression(
                Exp(.interpolate) {
                    Exp(.linear)
                    Exp(.zoom)
                    11.8
                    4
                    13
                    5
                    14
                    7
                    17
                    10
                    20
                    13
                }
            )
            selected.circleOpacity = .expression(
                Exp(.switchCase) {
                    isSelectedUnvisitedStatusExpression()
                    1.0
                    0.0
                }
            )
            selected.circleStrokeColor = .constant(StyleColor(.white))
            selected.circleStrokeWidth = .constant(2)
            selected.minZoom = addressLayerMinZoom
            selected.filter = pointFilter
            try map.addLayer(selected, layerPosition: .above(addressCircleLayerId))
        }

        var labels = SymbolLayer(id: addressNumberLayerId, source: sourceId)
        labels.sourceLayer = sourceLayer
        labels.textField = .expression(houseNumberLabelExpression())
        labels.textColor = .constant(StyleColor(.white))
        labels.textHaloColor = .constant(StyleColor(.black))
        labels.textHaloWidth = .constant(1.4)
        labels.textSize = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                17
                11.5
                20
                15
            }
        )
        labels.textAnchor = .constant(.center)
        labels.textJustify = .constant(.center)
        labels.textOffset = .constant([0, -0.35])
        labels.textPitchAlignment = .constant(.viewport)
        labels.textRotationAlignment = .constant(.viewport)
        labels.textVariableAnchor = .constant([.center])
        labels.textAllowOverlap = .constant(true)
        labels.textIgnorePlacement = .constant(true)
        labels.textOcclusionOpacity = .constant(1.0)
        labels.textOpacity = .expression(
            Self.linkedAddressNumberOpacityExpression(linkedExpression: Self.linkedAddressNumberExpression)
        )
        labels.symbolPlacement = .constant(.point)
        labels.symbolZOrder = .constant(.auto)
        if usesCirclePolygons {
            labels.symbolZElevate = .constant(true)
            labels.symbolElevationReference = .constant(.ground)
            labels.symbolZOffset = .expression(
                Exp(.sum) {
                    addressCylinderHeightExpression()
                    addressLabelCapClearanceMeters
                }
            )
        }
        labels.symbolSortKey = .expression(
            Exp(.coalesce) {
                Exp(.get) { "label_priority" }
                100
            }
        )
        labels.minZoom = Self.addressNumberLayerMinZoom
        labels.filter = addressNumberFilter(usesCirclePolygons: usesCirclePolygons)
        try map.addLayer(labels, layerPosition: .above(selectedAddressCircleLayerId))
    }

    private func scopedPointFilter() -> Exp {
        scopedPointOrLineFilter(pointGeometryFilter())
    }

    private func scopedPolygonFilter() -> Exp {
        polygonGeometryFilter()
    }

    private func addressGeometryFilter(usesCirclePolygons: Bool) -> Exp {
        usesCirclePolygons ? scopedPolygonFilter() : scopedPointFilter()
    }

    private func addressNumberFilter(usesCirclePolygons: Bool) -> Exp {
        Exp(.all) {
            addressGeometryFilter(usesCirclePolygons: usesCirclePolygons)
            Exp(.neq) {
                houseNumberLabelExpression()
                ""
            }
        }
    }

    private func scopedPointOrLineFilter(_ baseFilter: Exp) -> Exp {
        guard let territoryBoundary else { return baseFilter }
        return Exp(.all) {
            baseFilter
            Exp(.within) {
                territoryBoundary
            }
        }
    }

    private func pointGeometryFilter() -> Exp {
        Exp(.match) {
            Exp(.geometryType)
            "Point"
            true
            false
        }
    }

    private func polygonGeometryFilter() -> Exp {
        Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
    }

    private func addressCylinderHeightExpression() -> Exp {
        Exp(.max) {
            Exp(.toNumber) {
                Exp(.coalesce) {
                    Exp(.featureState) { "height_m" }
                    Exp(.get) { "height_m" }
                    Exp(.featureState) { "height" }
                    Exp(.get) { "height" }
                    addressCylinderHeightMeters
                }
            }
            addressCylinderHeightMeters
        }
    }

    private func addressCylinderBaseExpression() -> Exp {
        Exp(.max) {
            Exp(.toNumber) {
                Exp(.coalesce) {
                    Exp(.featureState) { "min_height" }
                    Exp(.get) { "min_height" }
                    0
                }
            }
            0
        }
    }

    private func diamondRenderableBuildingFilter() -> Exp {
        // Mapbox iOS currently does not evaluate `within` for Polygon/MultiPolygon
        // features. The PMTiles endpoints are already campaign-scoped; keep this
        // filter to renderable footprint geometry and minimum area only.
        Exp(.all) {
            polygonGeometryFilter()
            Exp(.switchCase) {
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.get) { "area_sqm" }
                        Exp(.get) { "area" }
                        999_999
                    }
                    0
                }
                Exp(.gte) {
                    Exp(.coalesce) {
                        Exp(.get) { "area_sqm" }
                        Exp(.get) { "area" }
                        999_999
                    }
                    30
                }
                true
            }
        }
    }

    private func leadGlowOpacityExpression() -> Exp {
        Exp(.switchCase) {
            Exp(.match) {
                statusValueExpression(defaultStatus: "none")
                ["appointment", "future_seller", "follow_up", "hot_lead"]
                true
                false
            }
            0.82
            0.0
        }
    }

    private func parcelLineOpacityExpression() -> Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            0.0
            Exp(.switchCase) {
                isSelectedExpression()
                1.0
                0.36
            }
            12.0
            Exp(.switchCase) {
                isSelectedExpression()
                1.0
                0.42
            }
            14.0
            Exp(.switchCase) {
                isSelectedExpression()
                1.0
                0.46
            }
            15.2
            Exp(.switchCase) {
                isSelectedExpression()
                1.0
                0.48
            }
            17.4
            Exp(.switchCase) {
                isSelectedExpression()
                1.0
                isActiveStatusExpression()
                0.9
                0.62
            }
            20.0
            Exp(.switchCase) {
                isSelectedExpression()
                1.0
                isActiveStatusExpression()
                0.82
                0.5
            }
        }
    }

    private func parcelOverviewFillOpacityExpression() -> Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            0.0
            Exp(.switchCase) {
                isSelectedExpression()
                0.42
                0.035
            }
            12.0
            Exp(.switchCase) {
                isSelectedExpression()
                0.42
                0.045
            }
            14.0
            Exp(.switchCase) {
                isSelectedExpression()
                0.42
                0.06
            }
            15.2
            Exp(.switchCase) {
                isSelectedExpression()
                0.42
                0.10
            }
            17.4
            Exp(.switchCase) {
                isSelectedExpression()
                0.42
                isActiveStatusExpression()
                0.18
                0.12
            }
            20.0
            Exp(.switchCase) {
                isSelectedExpression()
                0.42
                isActiveStatusExpression()
                0.14
                0.08
            }
        }
    }

    private func statusFillColorExpression(
        defaultColor: UIColor,
        selectedOverridesStatus: Bool = false
    ) -> Exp {
        return Exp(.switchCase) {
            selectedOverridesStatus ? isSelectedHighlightVisibleExpression() : isSelectedUnvisitedStatusExpression()
            MapStatusColor.selectedHome

            statusMatchColorExpression(defaultColor: defaultColor)
        }
    }

    private func statusMatchColorExpression(defaultColor: UIColor) -> Exp {
        Exp(.match) {
            statusValueExpression()
            "none"
            MapStatusColor.untouched
            "not_visited"
            MapStatusColor.untouched
            "unvisited"
            MapStatusColor.untouched
            "flyer_unvisited"
            MapStatusColor.flyerUntouched
            "no_answer"
            MapStatusColor.noOneHome
            "talked"
            MapStatusColor.conversations
            "hot"
            MapStatusColor.conversations
            "conversation"
            MapStatusColor.conversations
            "visited"
            MapStatusColor.touched
            "delivered"
            MapStatusColor.touched
            "lead"
            MapStatusColor.lead
            "future_seller"
            MapStatusColor.hotLead
            "hot_lead"
            MapStatusColor.lead
            "appointment"
            MapStatusColor.hotLead
            "follow_up"
            MapStatusColor.hotLead
            "do_not_knock"
            MapStatusColor.doNotKnock
            "not_interested"
            MapStatusColor.noOneHome
            defaultColor
        }
    }

    private func isSelectedExpression() -> Exp {
        Exp(.eq) {
            Exp(.coalesce) {
                Exp(.featureState) { "selected" }
                false
            }
            true
        }
    }

    private func isSelectedHighlightVisibleExpression() -> Exp {
        Exp(.all) {
            isSelectedExpression()
            Exp(.neq) {
                Exp(.coalesce) {
                    Exp(.featureState) { "suppress_selected_highlight" }
                    false
                }
                true
            }
        }
    }

    private func scansTotalExpression() -> Exp {
        Exp(.coalesce) {
            Exp(.featureState) { "scans_total" }
            Exp(.get) { "scans_total" }
            0
        }
    }

    private func isSelectedUnvisitedStatusExpression() -> Exp {
        Exp(.all) {
            isSelectedExpression()
            Exp(.lte) {
                scansTotalExpression()
                0
            }
            Exp(.match) {
                statusValueExpression()
                ["none", "not_visited", "unvisited", "flyer_unvisited"]
                true
                false
            }
        }
    }

    private func isActiveStatusExpression() -> Exp {
        Exp(.match) {
            statusValueExpression(defaultStatus: "not_visited")
            ["visited", "delivered", "talked", "hot", "conversation", "lead", "future_seller", "hot_lead", "appointment", "follow_up", "no_answer", "do_not_knock", "not_interested", "flyer_unvisited"]
            true
            false
        }
    }

    private func selectedBuildingHeightExpression(base: Exp) -> Exp {
        Exp(.switchCase) {
            isSelectedExpression()
            Exp(.product) {
                base
                selectedBuildingHeightScale
            }
            base
        }
    }

    private func statusValueExpression(defaultStatus: String = "not_visited") -> Exp {
        Exp(.coalesce) {
            Exp(.featureState) { "status" }
            Exp(.get) { "status" }
            Exp(.get) { "address_status" }
            Exp(.get) { "building_status" }
            Exp(.get) { "home_status" }
            defaultStatus
        }
    }
}

enum DiamondGeometryProviderError: LocalizedError {
    case unsupportedManifest
    case mapUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedManifest:
            return "Unsupported Diamond geometry manifest"
        case .mapUnavailable:
            return "Map is not ready for Diamond geometry"
        }
    }
}
