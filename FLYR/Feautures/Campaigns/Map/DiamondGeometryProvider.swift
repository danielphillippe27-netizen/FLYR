import Foundation
@_spi(Experimental) import MapboxMaps
import Supabase
import UIKit

@MainActor
protocol DiamondGeometryProvider {
    func installGeometry(
        for campaignId: String,
        manifest: DiamondManifest,
        on mapView: MapView
    ) async throws

    func removeGeometry(from mapView: MapView) throws
}

@MainActor
final class VectorTileDiamondGeometryProvider: DiamondGeometryProvider {
    static let sourceId = "diamond-buildings"
    static let parcelFillLayerId = "diamond-parcels-fill"
    static let parcelLineLayerId = "diamond-parcels-line"
    static let buildingFillLayerId = "diamond-buildings-fill"
    static let buildingLineLayerId = "diamond-buildings-line"
    static let buildingLeadGlowLayerId = "diamond-buildings-lead-glow"
    static let buildingAddressNumberLayerId = "diamond-buildings-address-numbers"
    static let addressCircleLayerId = "diamond-addresses-circles"
    static let selectedAddressCircleLayerId = "diamond-addresses-selected"
    static let addressNumberLayerId = "diamond-addresses-numbers"

    private let sourceId = VectorTileDiamondGeometryProvider.sourceId
    private let parcelFillLayerId = VectorTileDiamondGeometryProvider.parcelFillLayerId
    private let parcelLineLayerId = VectorTileDiamondGeometryProvider.parcelLineLayerId
    private let buildingFillLayerId = VectorTileDiamondGeometryProvider.buildingFillLayerId
    private let buildingLineLayerId = VectorTileDiamondGeometryProvider.buildingLineLayerId
    private let buildingLeadGlowLayerId = VectorTileDiamondGeometryProvider.buildingLeadGlowLayerId
    private let buildingAddressNumberLayerId = VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId
    private let addressCircleLayerId = VectorTileDiamondGeometryProvider.addressCircleLayerId
    private let selectedAddressCircleLayerId = VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId
    private let addressNumberLayerId = VectorTileDiamondGeometryProvider.addressNumberLayerId
    private let addressCylinderHeightMeters = 16.0
    private let selectedAddressCylinderHeightMeters = 18.0
    private let addressLabelCapClearanceMeters = 0.25
    private let selectedBuildingHeightScale = 1.16

    func installGeometry(
        for campaignId: String,
        manifest: DiamondManifest,
        on mapView: MapView
    ) async throws {
        guard manifest.isPMTilesGeometryProvider,
              let rawTileTemplate = manifest.vectorTileUrlTemplate,
              let buildingLayer = manifest.sourceLayers?.buildings else {
            throw DiamondGeometryProviderError.unsupportedManifest
        }

        let tileTemplate = await tileTemplateWithAccessToken(rawTileTemplate)
        guard let map = mapView.mapboxMap else {
            throw DiamondGeometryProviderError.mapUnavailable
        }

        try removeExistingDiamondLayers(from: map)

        var source = VectorSource(id: sourceId)
        source.tiles = [tileTemplate]
        source.minzoom = manifest.minzoom ?? 13
        source.maxzoom = manifest.maxzoom ?? 18
        source.bounds = manifest.bounds

        var promoteIds: [String: Value<String>] = [
            buildingLayer: .constant(manifest.promoteIds?.buildings ?? "address_id")
        ]
        if let parcelLayer = manifest.sourceLayers?.parcels {
            promoteIds[parcelLayer] = .constant(manifest.promoteIds?.parcels ?? "parcel_id")
        }
        if let addressCircleLayer = manifest.sourceLayers?.addressCircles {
            promoteIds[addressCircleLayer] = .constant(manifest.promoteIds?.addressCircles ?? manifest.promoteIds?.addresses ?? "address_id")
        }
        if let addressLayer = manifest.sourceLayers?.addresses {
            promoteIds[addressLayer] = .constant(manifest.promoteIds?.addresses ?? "address_id")
        }
        source.promoteId2 = .byLayer(promoteIds)

        try map.addSource(source)

        if let parcelLayer = manifest.sourceLayers?.parcels {
            try addParcelLayers(map: map, sourceLayer: parcelLayer)
        }
        try addBuildingLayers(map: map, sourceLayer: buildingLayer)
        if let addressLayer = manifest.sourceLayers?.addressCircles,
           !addressLayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try addAddressLayers(
                map: map,
                sourceLayer: addressLayer,
                usesCirclePolygons: true
            )
        } else if manifest.sourceLayers?.addresses?.isEmpty == false {
            print("💎 [DIAMOND] Ignoring point-only PMTiles address layer; address cylinders require an address_circles polygon source layer")
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
        if map.allSourceIdentifiers.contains(where: { $0.id == sourceId }) {
            try map.removeSource(withId: sourceId)
        }
    }

    private func tileTemplateWithAccessToken(_ tileTemplate: String) async -> String {
        guard let session = try? await SupabaseManager.shared.client.auth.session,
              let encodedToken = session.accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return tileTemplate
        }
        let separator = tileTemplate.contains("?") ? "&" : "?"
        return "\(tileTemplate)\(separator)access_token=\(encodedToken)"
    }

    private func addBuildingLayers(map: MapboxMap, sourceLayer: String) throws {
        let renderableFilter = diamondRenderableBuildingFilter()

        var fill = FillExtrusionLayer(id: buildingFillLayerId, source: sourceId)
        fill.sourceLayer = sourceLayer
        fill.fillExtrusionColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.untouched))
        fill.fillExtrusionHeight = .expression(
            selectedBuildingHeightExpression(
                base: Exp(.coalesce) {
                    Exp(.get) { "height_m" }
                    Exp(.get) { "height" }
                    8
                }
            )
        )
        fill.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
        fill.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
        fill.fillExtrusionBase = .constant(0)
        fill.fillExtrusionOpacity = .constant(1.0)
        fill.fillExtrusionVerticalGradient = .constant(true)
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
        selectedGlow.lineOpacity = .expression(
            Exp(.switchCase) {
                isSelectedExpression()
                0.72
                0.0
            }
        )
        selectedGlow.lineOpacityTransition = StyleTransition(duration: 0.2, delay: 0)
        selectedGlow.minZoom = 12
        selectedGlow.filter = renderableFilter

        try map.addLayer(selectedGlow, layerPosition: .above(buildingFillLayerId))

        try addBuildingAddressNumberLayer(map: map, sourceLayer: sourceLayer)

        // Lead/follow-up states are shown through the fill color. The line layer above is
        // selection-only, so normal homes do not carry an always-on footprint outline.
    }

    private func addBuildingAddressNumberLayer(map: MapboxMap, sourceLayer: String) throws {
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
                10
                20
                13
            }
        )
        labels.textAnchor = .constant(.center)
        labels.textJustify = .constant(.center)
        labels.textOffset = .constant([0, 0])
        labels.textPitchAlignment = .constant(.viewport)
        labels.textRotationAlignment = .constant(.viewport)
        labels.textVariableAnchor = .constant([.center])
        labels.textAllowOverlap = .constant(false)
        labels.textIgnorePlacement = .constant(false)
        labels.textOcclusionOpacity = .constant(1.0)
        labels.symbolPlacement = .constant(.point)
        labels.symbolZOrder = .constant(.auto)
        labels.symbolZElevate = .constant(true)
        labels.symbolElevationReference = .constant(.ground)
        labels.symbolZOffset = .expression(
            Exp(.sum) {
                Exp(.coalesce) {
                    Exp(.get) { "height_m" }
                    Exp(.get) { "height" }
                    8
                }
                addressLabelCapClearanceMeters
            }
        )
        labels.symbolSortKey = .constant(0)
        labels.minZoom = 17
        labels.filter = singleAddressBuildingNumberFilter()
        try map.addLayer(labels, layerPosition: .above(buildingLineLayerId))
    }

    private func houseNumberLabelExpression() -> Exp {
        Exp(.coalesce) {
            Exp(.get) { "house_number_label" }
            Exp(.get) { "house_number" }
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
            Exp(.any) {
                Exp(.has) { "linked_address_count" }
                Exp(.has) { "address_count" }
                Exp(.has) { "units_count" }
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

    private func addParcelLayers(map: MapboxMap, sourceLayer: String) throws {
        let parcelFilter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }

        var fill = FillLayer(id: parcelFillLayerId, source: sourceId)
        fill.sourceLayer = sourceLayer
        fill.fillColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.untouched))
        fill.fillOpacity = .constant(0.12)
        fill.fillAntialias = .constant(true)
        fill.minZoom = 12
        fill.filter = parcelFilter
        try map.addLayer(fill)

        var line = LineLayer(id: parcelLineLayerId, source: sourceId)
        line.sourceLayer = sourceLayer
        line.lineColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.untouched))
        line.lineOpacity = .constant(0.62)
        line.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                12
                0.35
                16
                0.75
                20
                1.1
            }
        )
        line.minZoom = 12
        line.filter = parcelFilter
        try map.addLayer(line, layerPosition: .above(parcelFillLayerId))
    }

    private func addAddressLayers(map: MapboxMap, sourceLayer: String, usesCirclePolygons: Bool) throws {
        let pointFilter = Exp(.match) {
            Exp(.geometryType)
            "Point"
            true
            false
        }
        let polygonFilter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        let addressFilter = usesCirclePolygons ? polygonFilter : pointFilter

        if usesCirclePolygons {
            var cylinders = FillExtrusionLayer(id: addressCircleLayerId, source: sourceId)
            cylinders.sourceLayer = sourceLayer
            cylinders.fillExtrusionColor = .expression(statusFillColorExpression(defaultColor: MapStatusColor.addressMarker))
            cylinders.fillExtrusionHeight = .constant(addressCylinderHeightMeters)
            cylinders.fillExtrusionBase = .constant(0)
            cylinders.fillExtrusionOpacity = .constant(0.98)
            cylinders.fillExtrusionVerticalGradient = .constant(true)
            cylinders.minZoom = 14
            cylinders.filter = polygonFilter
            try map.addLayer(cylinders)

            var selected = FillExtrusionLayer(id: selectedAddressCircleLayerId, source: sourceId)
            selected.sourceLayer = sourceLayer
            selected.fillExtrusionColor = .constant(StyleColor(MapStatusColor.selectedHome))
            selected.fillExtrusionHeight = .constant(selectedAddressCylinderHeightMeters)
            selected.fillExtrusionBase = .constant(0)
            selected.fillExtrusionOpacity = .expression(
                Exp(.switchCase) {
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "selected" }
                            false
                        }
                        true
                    }
                    1.0
                    0.0
                }
            )
            selected.fillExtrusionVerticalGradient = .constant(true)
            selected.minZoom = 14
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
            circles.minZoom = 14
            circles.filter = pointFilter
            try map.addLayer(circles)

            var selected = CircleLayer(id: selectedAddressCircleLayerId, source: sourceId)
            selected.sourceLayer = sourceLayer
            selected.circleColor = .constant(StyleColor(MapStatusColor.selectedHome))
            selected.circleRadius = .expression(
                Exp(.interpolate) {
                    Exp(.linear)
                    Exp(.zoom)
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
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "selected" }
                            false
                        }
                        true
                    }
                    1.0
                    0.0
                }
            )
            selected.circleStrokeColor = .constant(StyleColor(.white))
            selected.circleStrokeWidth = .constant(2)
            selected.minZoom = 14
            selected.filter = pointFilter
            try map.addLayer(selected, layerPosition: .above(addressCircleLayerId))
        }

        var labels = SymbolLayer(id: addressNumberLayerId, source: sourceId)
        labels.sourceLayer = sourceLayer
        labels.textField = .expression(
            Exp(.coalesce) {
                Exp(.get) { "house_number_label" }
                Exp(.get) { "house_number" }
                ""
            }
        )
        labels.textColor = .constant(StyleColor(.white))
        labels.textHaloColor = .constant(StyleColor(.black))
        labels.textHaloWidth = .constant(1.4)
        labels.textSize = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                17
                10
                20
                13
            }
        )
        labels.textAnchor = .constant(.center)
        labels.textJustify = .constant(.center)
        labels.textOffset = .constant([0, 0])
        labels.textPitchAlignment = .constant(.viewport)
        labels.textRotationAlignment = .constant(.viewport)
        labels.textVariableAnchor = .constant([.center])
        labels.textAllowOverlap = .constant(usesCirclePolygons)
        labels.textIgnorePlacement = .constant(usesCirclePolygons)
        labels.textOcclusionOpacity = .constant(1.0)
        labels.symbolPlacement = .constant(.point)
        labels.symbolZOrder = .constant(.auto)
        if usesCirclePolygons {
            labels.symbolZElevate = .constant(true)
            labels.symbolElevationReference = .constant(.ground)
            labels.symbolZOffset = .constant(addressCylinderHeightMeters + addressLabelCapClearanceMeters)
        }
        labels.symbolSortKey = .expression(
            Exp(.coalesce) {
                Exp(.get) { "label_priority" }
                100
            }
        )
        labels.minZoom = 17
        labels.filter = addressFilter
        try map.addLayer(labels, layerPosition: .above(selectedAddressCircleLayerId))
    }

    private func diamondRenderableBuildingFilter() -> Exp {
        Exp(.all) {
            Exp(.match) {
                Exp(.geometryType)
                "Polygon"
                true
                "MultiPolygon"
                true
                false
            }
            Exp(.match) {
                Exp(.downcase) {
                    Exp(.toString) {
                        Exp(.coalesce) {
                            Exp(.get) { "building_type" }
                            Exp(.get) { "subtype" }
                            Exp(.get) { "class" }
                            ""
                        }
                    }
                }
                ["shed", "garage", "garages", "carport", "parking", "parking_garage", "outbuilding", "accessory", "ancillary"]
                false
                true
            }
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

    private func statusFillColorExpression(defaultColor: UIColor) -> Exp {
        Exp(.switchCase) {
            isSelectedExpression()
            MapStatusColor.selectedHome

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
                MapStatusColor.hotLead
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
