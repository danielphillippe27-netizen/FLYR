import UIKit
import MapboxMaps
import Turf

/// Owns the campaign's local wolf, independently of multiplayer presence and server flags.
final class CampaignWolfLocationMarker {
    private weak var mapView: MapView?
    private let sourceID: String
    private let layerID = "campaign-local-wolf"
    private let trailSourceID = "campaign-wolf-paw-trail-source"
    private let trailLayerID = "campaign-wolf-paw-trail-layer"
    private let pawImageID = "campaign-wolf-paw-print"
    private var renderer: WolfyMapPrototypeRenderer?
    private var economyStore: WolfyEconomyStore?
    private var equipment: [String:String] = [:]
    private var appearance = WolfyAppearance()
    private var growthStage = 1
    private var growthRefreshInFlight = false
    private var lastGrowthRefresh = Date.distantPast
    private var timer: Timer?
    private var styleObservation: AnyCancelable?
    private var notifications: [NSObjectProtocol] = []
    private var location: CLLocation?
    private var heading: Double?
    private var show = false
    private var foreground = UIApplication.shared.applicationState != .background
    private var fallbackVisible: Bool?
    private var trailAnchor: CLLocation?
    private var trailLocations: [CLLocation] = []
    private var trailDistanceRemainder = 0.0
    private var pawTrailNeedsUpdate = true
    private var lastTrailFadeRender = Date.distantPast
    var diagnostic: String {
        "ready=\(renderer?.isReady == true), fallback=\(fallbackVisible == true), visible=\(show && foreground), \(renderer?.diagnostic ?? "no renderer")"
    }

    init(mapView: MapView, sourceID: String) {
        self.mapView = mapView
        self.sourceID = sourceID
        styleObservation = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            self?.renderer = nil
            self?.fallbackVisible = nil
            self?.refresh()
        }
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.foreground = false; self?.refresh()
        })
        notifications.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.foreground = true; self?.refresh()
        })
        notifications.append(center.addObserver(forName:.wolfyWardrobeDidChange, object:nil, queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshEquipment() }
        })
        Task { @MainActor [weak self] in
            self?.refreshEquipment()
            self?.refreshGrowthStage()
            guard let economy = self?.economyStore else { return }
            await economy.refresh()
            self?.refreshEquipment()
        }
    }

    @MainActor private func refreshEquipment() {
        guard let user = AuthManager.shared.user?.id,
              let workspace = WorkspaceContext.shared.workspaceId else { return }
        if economyStore?.user != user || economyStore?.workspace != workspace {
            economyStore = WolfyEconomyStore(user:user, workspace:workspace)
        }
        equipment = economyStore?.effectiveEquipment ?? [:]
        appearance = WolfyAppearance.saved(user:user,workspace:workspace)
        renderer?.setEquipment(equipment)
        renderer?.setAppearance(appearance)
        mapView?.mapboxMap.triggerRepaint()
    }

    @MainActor private func refreshGrowthStage() {
        guard !growthRefreshInFlight,
              let user = AuthManager.shared.user?.id,
              let workspace = WorkspaceContext.shared.workspaceId else { return }
        let key = "wolfy.growth.\(workspace).\(user)"
        let cached = UserDefaults.standard.integer(forKey:key)
        if cached > 0 {
            growthStage = min(5,cached)
            renderer?.setGrowthStage(growthStage)
        }
        growthRefreshInFlight = true
        lastGrowthRefresh = Date()
        Task { @MainActor [weak self] in
            let doors = (try? await StatsService.shared.fetchUserStats(userID:user))?.doors_knocked
            guard let self else { return }
            self.growthRefreshInFlight = false
            guard let doors, AuthManager.shared.user?.id == user,
                  WorkspaceContext.shared.workspaceId == workspace else { return }
            let previousStage = self.growthStage
            self.growthStage = WolfyProgression.growthStage(doors:doors)
            UserDefaults.standard.set(self.growthStage,forKey:key)
            self.renderer?.setGrowthStage(self.growthStage)
            self.mapView?.mapboxMap.triggerRepaint()
            if self.growthStage != previousStage {
                NotificationCenter.default.post(name: .wolfyWardrobeDidChange, object: nil)
            }
        }
    }

    func update(location: CLLocation?, heading: Double?, show: Bool) {
        if show, let location { appendPawSteps(toward: location) }
        else {
            trailAnchor = nil
            trailDistanceRemainder = 0
            if !trailLocations.isEmpty { trailLocations.removeAll(); pawTrailNeedsUpdate = true }
            if let map = mapView?.mapboxMap { updatePawTrail(on: map) }
        }
        self.location = location
        self.heading = heading
        self.show = show
        if fallbackVisible == true { fallbackVisible = nil }
        refresh()
    }

    private func refresh() {
        guard let mapView else { stop(); return }
        let active = show && foreground && location != nil
        if active {
            if timer == nil {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.frame() }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
            frame()
        } else {
            timer?.invalidate(); timer = nil
            renderer?.setVisible(false)
            updateFallback(visible: false)
            mapView.mapboxMap.triggerRepaint()
        }
    }

    private func frame() {
        guard let map = mapView?.mapboxMap, let location, show, foreground else { return }
        if Date().timeIntervalSince(lastGrowthRefresh) > 120 {
            Task { @MainActor [weak self] in self?.refreshGrowthStage() }
        }
        // The campaign owns style setup. Wait until its location source exists.
        guard map.sourceExists(withId: sourceID) else { return }
        installPawTrailIfNeeded(on: map)
        updatePawTrail(on: map)
        if !map.layerExists(withId: layerID) {
            let next = WolfyMapPrototypeRenderer(origin: location.coordinate, drawAboveBuildings: true)
            do {
                try map.addCustomLayer(withId: layerID, layerHost: next, layerPosition: nil)
                renderer = next
                next.setEquipment(equipment)
                next.setAppearance(appearance)
                next.setGrowthStage(growthStage)
            } catch {
                updateFallback(visible: true)
                return
            }
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
        renderer?.updateLocation(location.coordinate, heading: heading, speed: max(0, location.speed), animated: !reduceMotion)
        renderer?.setVisible(true)
        updateFallback(visible: renderer?.isReady != true)
        map.triggerRepaint()
    }

    private func appendPawSteps(toward location: CLLocation) {
        guard let previous = trailAnchor else { trailAnchor = location; return }
        let distance = previous.distance(from: location)
        guard distance > 0 else { return }
        let bearing = Self.bearing(from: previous.coordinate, to: location.coordinate)
        var distanceToNextStep = Self.stepSpacingMeters - trailDistanceRemainder
        var stepsAdded = 0
        while distanceToNextStep <= distance, stepsAdded < Self.visibleStepCount * 4 {
            let fraction = min(1, distanceToNextStep / distance)
            let coordinate = CLLocationCoordinate2D(
                latitude: previous.coordinate.latitude + (location.coordinate.latitude - previous.coordinate.latitude) * fraction,
                longitude: previous.coordinate.longitude + (location.coordinate.longitude - previous.coordinate.longitude) * fraction
            )
            let alternatingOffset = trailLocations.count.isMultiple(of: 2) ? 16.0 : -16.0
            let stamp = CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 0, verticalAccuracy: 0, course: bearing + alternatingOffset, speed: 0, timestamp: Date())
            trailLocations.append(stamp)
            if trailLocations.count > Self.visibleStepCount { trailLocations.removeFirst() }
            stepsAdded += 1
            distanceToNextStep += Self.stepSpacingMeters
        }
        trailDistanceRemainder = (trailDistanceRemainder + distance).truncatingRemainder(dividingBy: Self.stepSpacingMeters)
        trailAnchor = location
        if stepsAdded > 0 { pawTrailNeedsUpdate = true }
    }

    private func installPawTrailIfNeeded(on map: MapboxMap) {
        do {
            if !map.sourceExists(withId: trailSourceID) {
                var source = GeoJSONSource(id: trailSourceID)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)
                pawTrailNeedsUpdate = true
            }
            if !map.imageExists(withId: pawImageID) {
                try map.addImage(Self.makePawImage(), id: pawImageID)
            }
            if !map.layerExists(withId: trailLayerID) {
                var layer = SymbolLayer(id: trailLayerID, source: trailSourceID)
                layer.iconImage = .constant(.name(pawImageID))
                layer.iconSize = .expression(Exp(.get) { "scale" })
                layer.iconRotate = .expression(Exp(.get) { "heading" })
                layer.iconRotationAlignment = .constant(.map)
                layer.iconAllowOverlap = .constant(true)
                layer.iconIgnorePlacement = .constant(true)
                layer.iconOpacity = .expression(Exp(.get) { "opacity" })
                try map.addLayer(layer)
            }
        } catch {
            print("⚠️ [CampaignWolf] Could not install paw trail: \(error)")
        }
    }

    private func updatePawTrail(on map: MapboxMap) {
        let now = Date()
        guard map.sourceExists(withId: trailSourceID),
              pawTrailNeedsUpdate || (!trailLocations.isEmpty && now.timeIntervalSince(lastTrailFadeRender) >= Self.fadeRefreshInterval) else { return }
        let features = trailLocations.enumerated().map { index, location -> Feature in
            var feature = Feature(geometry: .point(Point(location.coordinate)))
            let age = max(0, now.timeIntervalSince(location.timestamp))
            let fade = max(0, 1 - age / Self.fadeDuration)
            let recency = Double(index + 1) / Double(max(1, trailLocations.count))
            feature.properties = [
                "heading": .number(location.course),
                "opacity": .number((0.58 + 0.32 * recency) * fade),
                "scale": .number((0.30 + 0.12 * fade) * (1 - age / Self.fadeDuration * 0.18))
            ]
            return feature
        }
        map.updateGeoJSONSource(withId: trailSourceID, geoJSON: .featureCollection(FeatureCollection(features: features)))
        pawTrailNeedsUpdate = false
        lastTrailFadeRender = now
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let delta = (end.longitude - start.longitude) * .pi / 180
        return atan2(sin(delta) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)) * 180 / .pi
    }

    private static func makePawImage() -> UIImage {
        let size = CGSize(width: 48, height: 48)
        return UIGraphicsImageRenderer(size: size).image { context in
            let color = UIColor(red: 0.30, green: 0.20, blue: 0.15, alpha: 1)
            color.setFill()
            let pads: [(CGRect, CGFloat)] = [
                (CGRect(x: 7, y: 8, width: 11, height: 14), -22),
                (CGRect(x: 19, y: 3, width: 11, height: 14), -5),
                (CGRect(x: 32, y: 8, width: 10, height: 14), 18),
                (CGRect(x: 10, y: 23, width: 28, height: 21), 0)
            ]
            for (rect, angle) in pads {
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: rect.midX, y: rect.midY)
                context.cgContext.rotate(by: angle * .pi / 180)
                UIBezierPath(ovalIn: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)).fill()
                context.cgContext.restoreGState()
            }
        }
    }

    private static let stepSpacingMeters = 0.72
    private static let visibleStepCount = 8
    private static let fadeDuration = 5.5
    private static let fadeRefreshInterval = 0.15

    private func updateFallback(visible: Bool) {
        guard let map = mapView?.mapboxMap, map.sourceExists(withId: sourceID), fallbackVisible != visible else { return }
        fallbackVisible = visible
        let features: [Feature]
        if visible, let location {
            features = [Feature(geometry: .point(Point(location.coordinate)))]
        } else {
            features = []
        }
        map.updateGeoJSONSource(withId: sourceID, geoJSON: .featureCollection(FeatureCollection(features: features)))
    }

    func stop() {
        timer?.invalidate(); timer = nil
        renderer?.setVisible(false)
        trailAnchor = nil
        trailLocations.removeAll()
        trailDistanceRemainder = 0
        pawTrailNeedsUpdate = true
        if let map = mapView?.mapboxMap { updatePawTrail(on: map) }
        styleObservation?.cancel(); styleObservation = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
    }

    deinit { stop() }
}
