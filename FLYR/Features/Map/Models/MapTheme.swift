import Foundation
import MapboxMaps
import UIKit

/// Helper for loading Mapbox style JSON files from bundle
struct MapTheme {
    private static let blueLightSkyLayerId = "flyr-blue-light-sky"
    private static let blueLightBackgroundLayerId = "flyr-blue-light-background"
    private static let lightAtmosphereBlueHex = "#85c7f2"
    private static let lightAtmosphereHighBlueHex = "#b9e1ff"
    private static let lightAtmosphereHorizonHex = "#e6f5ff"
    private static let lightModeFlatPitchThreshold: CGFloat = 1.0
    private static let lightModePitchedShadowIntensity = 0.18
    private static let transparentBasemapBuildingColor = StyleColor(red: 255, green: 255, blue: 255, alpha: 0)!
    static let lightAtmosphereBlue = UIColor(red: 0.52, green: 0.78, blue: 0.95, alpha: 1.0)

    static func loadBlueStandardLightStyle(on map: MapboxMap) {
        map.load(mapStyle: blueStandardLightStyle)
        applyBlueLightAtmosphereWhenStyleLoads(on: map)
    }

    static func loadStyle(for mode: MapMode, preferLightStyle: Bool = false, on map: MapboxMap) {
        if mode == .light || (mode == .campaign3D && preferLightStyle) {
            loadBlueStandardLightStyle(on: map)
        } else {
            map.loadStyle(styleURI(for: mode, preferLightStyle: preferLightStyle))
            hideBaseMapAddressNumberLayersWhenStyleLoads(on: map)
        }
    }

    private static var blueStandardLightStyle: MapboxMaps.MapStyle {
        .standard(
            theme: .default,
            lightPreset: .day,
            show3dObjects: false,
            colorBuildingHighlight: transparentBasemapBuildingColor,
            colorBuildings: transparentBasemapBuildingColor,
            colorBuildingSelect: transparentBasemapBuildingColor,
            show3dBuildings: false,
            show3dFacades: false,
            show3dLandmarks: false,
            show3dTrees: false
        )
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

        do {
            try disableStandard3DObjects(on: map)
        } catch {
            print("⚠️ [MapTheme] Failed to disable Standard 3D objects: \(error)")
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
        let currentPitch = pitch ?? map.cameraState.pitch
        let isFlat2D = currentPitch <= lightModeFlatPitchThreshold
        let shadowIntensity = isFlat2D ? 0.0 : lightModePitchedShadowIntensity
        let castsShadows = !isFlat2D

        do {
            let directionalLight = DirectionalLight(id: "flyr-light-directional")
                .color(.white)
                .intensity(0.34)
                .direction(azimuthal: 210.0, polar: 38.0)
                .directionTransition(.zero)
                .castShadows(castsShadows)
                .shadowIntensity(shadowIntensity)
                .shadowIntensityTransition(.zero)

            let ambientLight = AmbientLight(id: "flyr-light-ambient")
                .color(.white)
                .intensity(isFlat2D ? 0.92 : 0.78)
                .intensityTransition(.zero)

            try map.setLights(ambient: ambientLight, directional: directionalLight)
        } catch {
            print("⚠️ [MapTheme] Failed to apply light-mode shadow policy: \(error)")
        }
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
        for layer in map.allLayerIdentifiers where isBaseMapAddressNumberLayer(layer) {
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

    private static func isBaseMapAddressNumberLayer(_ layer: LayerInfo) -> Bool {
        guard layer.type == .symbol else { return false }

        let lowercasedId = layer.id.lowercased()
        guard !isAppOwnedLayerId(lowercasedId) else { return false }

        return lowercasedId.contains("housenum")
            || lowercasedId.contains("house-number")
            || lowercasedId.contains("house_number")
            || lowercasedId.contains("address-number")
            || lowercasedId.contains("address_number")
            || lowercasedId.contains("building-number")
            || lowercasedId.contains("building_number")
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
            hideBaseMapAddressNumberLayers(on: map)
        }
        _ = map.onStyleLoaded.observeNext { _ in
            hideBaseMapAddressNumberLayers(on: map)
        }
        _ = map.onMapLoaded.observeNext { _ in
            hideBaseMapAddressNumberLayers(on: map)
        }
        _ = map.onMapIdle.observeNext { _ in
            hideBaseMapAddressNumberLayers(on: map)
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

    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/streets-v11")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!
}
