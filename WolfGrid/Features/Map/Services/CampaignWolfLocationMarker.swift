import UIKit
import MapboxMaps
import Turf

/// Owns the campaign's local wolf, independently of multiplayer presence and server flags.
final class CampaignWolfLocationMarker {
    private weak var mapView: MapView?
    private let sourceID: String
    private let layerID = "campaign-local-wolf"
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
    private var useWolf = true
    private var foreground = UIApplication.shared.applicationState != .background
    private var fallbackVisible: Bool?
    private var motionPolicy = WolfMapMotionPolicy()
    private var continuousUpdates = false
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
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
                     UIAccessibility.reduceMotionStatusDidChangeNotification,
                     ProcessInfo.thermalStateDidChangeNotification] {
            notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
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

    func update(location: CLLocation?, heading: Double?, show: Bool, useWolf: Bool = true) {
        // Session timers and unrelated UI state can resend the same location.
        // Style/foreground observers independently refresh the existing marker.
        guard self.location !== location || self.heading != heading || self.show != show || self.useWolf != useWolf else { return }
        self.location = location
        self.heading = heading
        self.show = show
        self.useWolf = useWolf
        if fallbackVisible == true { fallbackVisible = nil }
        refresh()
    }

    private func refresh() {
        guard let mapView else { stop(); return }
        let active = show && foreground && location != nil
        if active && !useWolf {
            stopTimer()
            renderer?.setVisible(false)
            updateFallback(visible: true)
            mapView.mapboxMap.triggerRepaint()
        } else if active {
            frame()
        } else {
            stopTimer()
            motionPolicy.reset()
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
        let constrained = UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        let schedule = motionPolicy.schedule(now: ProcessInfo.processInfo.systemUptime,
                                             speed: max(0, location.speed), constrained: constrained)
        scheduleUpdate(schedule)
        // The campaign owns style setup. Wait until its location source exists.
        guard map.sourceExists(withId: sourceID) else { return }
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
        renderer?.updateLocation(location.coordinate, heading: heading, speed: max(0, location.speed), animated: schedule.animated)
        renderer?.setVisible(true)
        updateFallback(visible: renderer?.isReady != true)
        map.triggerRepaint()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        continuousUpdates = false
    }

    private func scheduleUpdate(_ schedule: WolfMapMotionPolicy.Schedule) {
        guard let interval = schedule.nextUpdate else { stopTimer(); return }
        if schedule.animated && continuousUpdates && timer != nil { return }
        stopTimer()
        continuousUpdates = schedule.animated
        let timer = Timer(timeInterval: interval, repeats: schedule.animated) { [weak self] _ in
            self?.frame()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
        stopTimer()
        renderer?.setVisible(false)
        motionPolicy.reset()
        styleObservation?.cancel(); styleObservation = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
    }

    deinit { stop() }
}
