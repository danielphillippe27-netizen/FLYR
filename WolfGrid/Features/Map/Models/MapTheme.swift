import Foundation
@_spi(Experimental) import MapboxMaps
import UIKit

/// Helper for loading Mapbox style JSON files from bundle
struct MapTheme {
    private static let blueLightSkyLayerId = "flyr-blue-light-sky"
    private static let blueLightBackgroundLayerId = "flyr-blue-light-background"
    private static let lightAtmosphereBlueHex = "#85c7f2"
    private static let lightAtmosphereHighBlueHex = "#b9e1ff"
    private static let lightAtmosphereHorizonHex = "#e6f5ff"
    private static let transparentBasemapBuildingColor = StyleColor(red: 255, green: 255, blue: 255, alpha: 0)!
    private static var retainedStyleObservers: [AnyCancelable] = []
    static let lightAtmosphereBlue = UIColor(red: 0.52, green: 0.78, blue: 0.95, alpha: 1.0)

    /// Hosted style URIs cached by `MapboxOfflineService` for campaign field use (must stay in sync).
    static let campaignOfflineLightStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/light-v11")!
    static let campaignOfflineDarkStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!
    static let campaignSatelliteStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/satellite-streets-v12")!

    static var campaignOfflineStyleURIs: [StyleURI] {
        [campaignOfflineLightStyleURI, campaignOfflineDarkStyleURI]
    }

    /// Load the campaign map basemap with the same Mapbox styling used before the
    /// local-style experiment, so roads and basemap features remain visible.
    static func loadCampaignMapStyle(
        useDarkStyle: Bool,
        useSatelliteStyle: Bool = false,
        preferOfflineStylePacks: Bool,
        on map: MapboxMap
    ) {
        MapStatusColor.useLightMapBuildingDefault = !useDarkStyle || useSatelliteStyle

        if useSatelliteStyle {
            map.loadStyle(campaignSatelliteStyleURI)
            hideBaseMapAddressNumberLayersWhenStyleLoads(on: map)
        } else if useDarkStyle {
            map.loadStyle(campaignOfflineDarkStyleURI)
            hideBaseMapAddressNumberLayersWhenStyleLoads(on: map)
        } else {
            loadBlueStandardLightStyle(on: map)
        }
        print("📴 [MapTheme] Loaded campaign Mapbox style useDarkStyle=\(useDarkStyle) useSatelliteStyle=\(useSatelliteStyle) preferOfflineStylePacks=\(preferOfflineStylePacks)")
    }

    static func loadBlueStandardLightStyle(on map: MapboxMap) {
        map.loadStyle(campaignOfflineLightStyleURI)
        applyBlueLightAtmosphereWhenStyleLoads(on: map)
        hideBaseMapAddressNumberLayersWhenStyleLoads(on: map)
    }

    /// Mapbox Maps v11 Standard with native 3D homes and explicit day/night styling.
    static func loadStandard3DHomesStyle(useDarkStyle: Bool, on map: MapboxMap) {
        MapStatusColor.useLightMapBuildingDefault = !useDarkStyle
        map.loadStyle(.standard)
        retainStyleObserver(map.onStyleLoaded.observeNext { _ in
            do {
                try map.setStyleImportConfigProperties(
                    for: "basemap",
                    configs: [
                        "lightPreset": useDarkStyle ? "night" : "day",
                        "show3dObjects": true,
                        "show3dBuildings": true,
                        "show3dFacades": true,
                        "show3dLandmarks": false,
                        "show3dTrees": false
                    ]
                )
            } catch {
                print("⚠️ [MapTheme] Failed to configure Standard 3D homes: \(error)")
            }
        })
    }

    static func loadStyle(for mode: MapMode, preferLightStyle: Bool = false, on map: MapboxMap) {
        let usesLightStyle = mode == .light || (mode == .campaign3D && preferLightStyle)
        MapStatusColor.useLightMapBuildingDefault = usesLightStyle

        if usesLightStyle {
            loadBlueStandardLightStyle(on: map)
        } else {
            map.loadStyle(styleURI(for: mode, preferLightStyle: preferLightStyle))
            hideBaseMapAddressNumberLayersWhenStyleLoads(on: map)
        }
    }

    /// A daylight globe atmosphere for light-mode maps so the horizon/sky stays blue without flattening the projection.
    static func applyBlueLightAtmosphere(to map: MapboxMap) {
        do {
            try map.setProjection(StyleProjection(name: .globe))
        } catch {
            print("⚠️ [MapTheme] Failed to force globe projection for v11 light style: \(error)")
        }

        do {
            let atmosphere = Atmosphere()
                .range(start: -2.0, end: 20.0)
                .verticalRange(start: 0.0, end: 0.0)
                .horizonBlend(1.0)
                .starIntensity(0.0)
                .color(UIColor(hex: lightAtmosphereHorizonHex) ?? UIColor(red: 0.90, green: 0.96, blue: 1.0, alpha: 1.0))
                .highColor(UIColor(hex: lightAtmosphereHighBlueHex) ?? UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1.0))
                .spaceColor(lightAtmosphereBlue)
            try map.setAtmosphere(atmosphere)
        } catch {
            print("⚠️ [MapTheme] Failed to apply blue light atmosphere: \(error)")
        }

        hideBaseMapBuildingLayers(on: map)
        hideBaseMapAddressNumberLayers(on: map)

        do {
            try applyBlueLightBackground(to: map)
        } catch {
            print("⚠️ [MapTheme] Failed to apply blue light background: \(error)")
        }

        do {
            try applyBlueLightSkyLayer(to: map)
        } catch {
            print("⚠️ [MapTheme] Failed to apply blue light sky layer: \(error)")
        }

        applyLightModeShadowPolicy(to: map)
    }

    static func applyLightModeShadowPolicy(to map: MapboxMap, pitch: CGFloat? = nil) {
        // Keep light mode visually consistent while the camera moves between
        // top-down and pitched views. The pitch argument remains in the API so
        // existing camera call sites do not need special-case behavior.
        _ = pitch

        do {
            let directionalLight = DirectionalLight(id: "flyr-light-directional")
                .color(UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0))
                .intensity(0.68)
                .direction(azimuthal: 210.0, polar: 38.0)
                .directionTransition(StyleTransition(duration: 0.25, delay: 0))
                .castShadows(true)
                .shadowIntensity(0.42)
                .shadowIntensityTransition(StyleTransition(duration: 0.25, delay: 0))

            let ambientLight = AmbientLight(id: "flyr-light-ambient")
                .color(UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1.0))
                .intensity(0.46)
                .intensityTransition(StyleTransition(duration: 0.25, delay: 0))

            try map.setLights(ambient: ambientLight, directional: directionalLight)
        } catch {
            print("⚠️ [MapTheme] Failed to apply light-mode shadow policy: \(error)")
        }
    }

    /// Gives custom GeoJSON/PMTiles extrusions the same dimensional response as
    /// Mapbox Standard buildings without making status colors look self-lit.
    /// Edge radius is measured in meters and Mapbox currently supports 0...1.
    static func configureExtrusionDepth(
        _ layer: inout FillExtrusionLayer,
        emissiveStrength: Double = 0.12,
        edgeRadius: Double = 0.6,
        roundedRoof: Bool = false
    ) {
        layer.fillExtrusionVerticalGradient = .constant(true)
        layer.fillExtrusionCastShadows = .constant(true)
        layer.fillExtrusionAmbientOcclusionIntensity = .constant(0.32)
        layer.fillExtrusionEmissiveStrength = .constant(emissiveStrength)
        layer.fillExtrusionEdgeRadius = .constant(min(max(edgeRadius, 0), 1))
        // Complex concave footprints can produce broken roof tessellation at
        // close zoom. Side-only rounding keeps the smooth silhouette stable.
        layer.fillExtrusionRoundedRoof = .constant(roundedRoof)
    }

    private static func disableStandard3DObjects(on map: MapboxMap) throws {
        try map.setStyleImportConfigProperties(
            for: "basemap",
            configs: [
                "show3dObjects": false,
                "colorBuildingHighlight": transparentBasemapBuildingColor.rawValue,
                "colorBuildings": transparentBasemapBuildingColor.rawValue,
                "colorBuildingSelect": transparentBasemapBuildingColor.rawValue,
                "show3dBuildings": false,
                "show3dFacades": false,
                "show3dLandmarks": false,
                "show3dTrees": false
            ]
        )
    }

    static func hideBaseMapBuildingLayers(on map: MapboxMap) {
        for layer in map.allLayerIdentifiers where isBaseMapBuildingLayerId(layer.id) {
            do {
                try map.setLayerProperty(for: layer.id, property: "visibility", value: "none")
            } catch {
                try? map.removeLayer(withId: layer.id)
            }
        }
    }

    static func hideBaseMapAddressNumberLayers(on map: MapboxMap) {
        for layer in map.allLayerIdentifiers where isBaseMapAddressNumberLayer(layer, on: map) {
            do {
                try map.setLayerProperty(for: layer.id, property: "visibility", value: "none")
            } catch {
                try? map.removeLayer(withId: layer.id)
            }
        }
    }

    private static func isBaseMapBuildingLayerId(_ id: String) -> Bool {
        let lowercasedId = id.lowercased()
        let isBuildingFootprintLayer = lowercasedId.contains("building")
            || lowercasedId.contains("structure")
            || lowercasedId.contains("footprint")
        guard isBuildingFootprintLayer else { return false }

        let appLayerPrefixes = [
            "flyr-",
            "campaign-",
            "buildings-",
            "crushed-buildings",
            "townhome-",
            "manual-"
        ]
        return !appLayerPrefixes.contains { lowercasedId.hasPrefix($0) }
    }

    private static func isBaseMapAddressNumberLayer(_ layer: LayerInfo, on map: MapboxMap) -> Bool {
        guard layer.type == .symbol else { return false }

        let lowercasedId = layer.id.lowercased()
        guard !isAppOwnedLayerId(lowercasedId) else { return false }

        if isAddressNumberToken(lowercasedId) {
            return true
        }

        guard let properties = try? map.layerProperties(for: layer.id) else { return false }
        let propertyText = flattenStyleValue(properties).lowercased()
        return isAddressNumberToken(propertyText)
    }

    private static func isAddressNumberToken(_ value: String) -> Bool {
        value.contains("housenum")
            || value.contains("house-num")
            || value.contains("house num")
            || value.contains("housenumber")
            || value.contains("house-number")
            || value.contains("house number")
            || value.contains("house_number")
            || value.contains("house_no")
            || value.contains("house-no")
            || value.contains("street_number")
            || value.contains("street-number")
            || value.contains("street number")
            || value.contains("street_no")
            || value.contains("street-no")
            || value.contains("addr:housenumber")
            || value.contains("addr_housenumber")
            || value.contains("addressnum")
            || value.contains("address-num")
            || value.contains("address num")
            || value.contains("address-number")
            || value.contains("address number")
            || value.contains("address_number")
            || value.contains("building-number")
            || value.contains("building number")
            || value.contains("building_number")
    }

    private static func retainStyleObserver(_ observer: AnyCancelable) {
        retainedStyleObservers.append(observer)
        if retainedStyleObservers.count > 48 {
            retainedStyleObservers.removeFirst(retainedStyleObservers.count - 48)
        }
    }

    private static func flattenStyleValue(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            return array.map(flattenStyleValue).joined(separator: " ")
        }
        if let dictionary = value as? [String: Any] {
            return dictionary
                .map { "\($0.key) \(flattenStyleValue($0.value))" }
                .joined(separator: " ")
        }
        return String(describing: value)
    }

    private static func isAppOwnedLayerId(_ lowercasedId: String) -> Bool {
        let appLayerPrefixes = [
            "flyr-",
            "campaign-",
            "buildings-",
            "crushed-buildings",
            "townhome-",
            "manual-",
            "session-"
        ]
        return appLayerPrefixes.contains { lowercasedId.hasPrefix($0) }
    }

    private static func applyBlueLightBackground(to map: MapboxMap) throws {
        for layer in map.allLayerIdentifiers where layer.type == .background {
            try map.setLayerProperty(for: layer.id, property: "background-color", value: lightAtmosphereBlueHex)
            try map.setLayerProperty(for: layer.id, property: "background-opacity", value: 1.0)
        }

        guard !map.layerExists(withId: blueLightBackgroundLayerId) else { return }
        let backgroundLayer: [String: Any] = [
            "id": blueLightBackgroundLayerId,
            "type": "background",
            "paint": [
                "background-color": lightAtmosphereBlueHex,
                "background-opacity": 1.0
            ]
        ]
        try map.addLayer(with: backgroundLayer, layerPosition: .at(0))
    }

    private static func applyBlueLightSkyLayer(to map: MapboxMap) throws {
        let gradientExpression: [Any] = [
            "interpolate",
            ["linear"],
            ["sky-radial-progress"],
            0.0,
            lightAtmosphereHorizonHex,
            0.65,
            lightAtmosphereHighBlueHex,
            1.0,
            lightAtmosphereBlueHex
        ]

        if map.layerExists(withId: blueLightSkyLayerId) {
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-type", value: "gradient")
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-gradient", value: gradientExpression)
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-gradient-center", value: [0.0, 0.0])
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-gradient-radius", value: 180.0)
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-atmosphere-sun", value: [0.0, 90.0])
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-atmosphere-sun-intensity", value: 15.0)
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-atmosphere-color", value: lightAtmosphereBlueHex)
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-atmosphere-halo-color", value: lightAtmosphereHorizonHex)
            try map.setLayerProperty(for: blueLightSkyLayerId, property: "sky-opacity", value: 1.0)
            return
        }

        let skyLayer: [String: Any] = [
            "id": blueLightSkyLayerId,
            "type": "sky",
            "paint": [
                "sky-type": "gradient",
                "sky-gradient": gradientExpression,
                "sky-gradient-center": [0.0, 0.0],
                "sky-gradient-radius": 180.0,
                "sky-atmosphere-sun": [0.0, 90.0],
                "sky-atmosphere-sun-intensity": 15.0,
                "sky-atmosphere-color": lightAtmosphereBlueHex,
                "sky-atmosphere-halo-color": lightAtmosphereHorizonHex,
                "sky-opacity": 1.0
            ]
        ]
        try map.addLayer(with: skyLayer, layerPosition: nil)
    }

    static func applyBlueLightAtmosphereWhenStyleLoads(on map: MapboxMap) {
        if map.isStyleLoaded {
            applyBlueLightAtmosphere(to: map)
        }
        _ = map.onStyleLoaded.observeNext { _ in
            applyBlueLightAtmosphere(to: map)
        }
        _ = map.onMapLoaded.observeNext { _ in
            applyBlueLightAtmosphere(to: map)
        }
        _ = map.onMapIdle.observeNext { _ in
            applyBlueLightAtmosphere(to: map)
        }
    }

    static func hideBaseMapAddressNumberLayersWhenStyleLoads(on map: MapboxMap) {
        if map.isStyleLoaded {
            hideBaseMapAddressNumberLayersWithRetries(on: map)
        }
        retainStyleObserver(map.onStyleLoaded.observeNext { _ in
            hideBaseMapAddressNumberLayersWithRetries(on: map)
        })
        retainStyleObserver(map.onMapLoaded.observeNext { _ in
            hideBaseMapAddressNumberLayersWithRetries(on: map)
        })
        retainStyleObserver(map.onMapIdle.observeNext { _ in
            hideBaseMapAddressNumberLayersWithRetries(on: map)
        })
    }

    private static func hideBaseMapAddressNumberLayersWithRetries(on map: MapboxMap) {
        hideBaseMapAddressNumberLayers(on: map)

        // Some Mapbox styles resolve imported symbol layers just after the first style
        // callback. Re-assert only this address-number rule without changing app layers.
        for delay in [0.15, 0.45, 0.9, 1.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                hideBaseMapAddressNumberLayers(on: map)
            }
        }
    }

    /// Get the bundle URL for the first available style JSON file in search order.
    private static func url(forFileNames fileNames: [String]) -> URL? {
        // Try multiple possible bundle subdirectories
        let possiblePaths = [
            "Features/Map/Styles",
            "Styles",
            nil // Root of bundle
        ]
        
        for fileName in fileNames {
            for subdirectory in possiblePaths {
                if let url = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: subdirectory) {
                    return url
                }
            }
        }
        return nil
    }
    
    /// Get style URI for a map mode (fallback to default if JSON not found)
    static func styleURI(for mode: MapMode) -> StyleURI {
        styleURI(for: mode, preferLightStyle: false)
    }

    /// Get style URI for a map mode, optionally using light base for 3D modes (e.g. campaign3D in light view)
    static func styleURI(for mode: MapMode, preferLightStyle: Bool) -> StyleURI {
        let styleCandidates: [String]
        switch mode {
        case .light:
            styleCandidates = ["LightStyle"]
        case .dark:
            styleCandidates = ["DarkStyle"]
        case .black3D:
            styleCandidates = ["BlackWhite3DStyle", "DarkStyle"]
        case .campaign3D:
            // Campaign3DStyle is optional in current app builds.
            // Fall back to base light/dark style JSON before using hosted style URIs.
            styleCandidates = preferLightStyle
                ? ["Campaign3DStyle", "LightStyle", "DarkStyle"]
                : ["Campaign3DStyle", "DarkStyle", "LightStyle"]
        }

        if let url = url(forFileNames: styleCandidates), let styleURI = StyleURI(url: url) {
            return styleURI
        }
        print("ℹ️ [MapTheme] No bundled JSON style found for mode=\(mode.rawValue) candidates=\(styleCandidates.joined(separator: ",")); using hosted style URI")
        
        // Fallback to custom Mapbox styles
        switch mode {
        case .light:
            return lightStyleURI
        case .dark:
            return darkStyleURI
        case .black3D:
            return darkStyleURI
        case .campaign3D:
            // Respect current view: light view → light base; dark view → dark base
            return preferLightStyle ? lightStyleURI : darkStyleURI
        }
    }

    private static let lightStyleURI = campaignOfflineLightStyleURI
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!
}
