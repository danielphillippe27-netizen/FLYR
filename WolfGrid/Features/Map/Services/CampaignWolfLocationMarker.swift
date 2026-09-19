import UIKit
import MapboxMaps
import Turf

/// Owns the campaign's local wolf, independently of multiplayer presence and server flags.
final class CampaignWolfLocationMarker {
    private weak var mapView: MapView?
    private let sourceID: String
    private let layerID = "campaign-local-wolf"
    private var renderer: WolfyMapPrototypeRenderer?
    private var timer: Timer?
    private var styleObservation: AnyCancelable?
    private var notifications: [NSObjectProtocol] = []
    private var location: CLLocation?
    private var heading: Double?
    private var show = false
    private var foreground = UIApplication.shared.applicationState != .background
    private var fallbackVisible: Bool?
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
    }

    func update(location: CLLocation?, heading: Double?, show: Bool) {
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
        // The campaign owns style setup. Wait until its location source exists.
        guard map.sourceExists(withId: sourceID) else { return }
        if !map.layerExists(withId: layerID) {
            let next = WolfyMapPrototypeRenderer(origin: location.coordinate, drawAboveBuildings: true)
            do {
                try map.addCustomLayer(withId: layerID, layerHost: next, layerPosition: nil)
                renderer = next
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
        styleObservation?.cancel(); styleObservation = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
    }

    deinit { stop() }
}
