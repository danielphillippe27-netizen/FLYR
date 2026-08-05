import UIKit
import MapboxMaps

@MainActor
final class LiveCampaignMapSnapshotStore {
    static let shared = LiveCampaignMapSnapshotStore()

    private static let summaryFlyDuration: TimeInterval = 0.8
    private static let summarySettleDelayNanoseconds: UInt64 = 180_000_000
    private static let privacyHideSettleDelayNanoseconds: UInt64 = 140_000_000

    private init() {}

    weak var mapView: MapView?
    private var preferredSummaryCamera: CameraOptions?

    func setMapView(_ mapView: MapView?) {
        self.mapView = mapView
    }

    func setPreferredSummaryCamera(_ camera: CameraOptions?) {
        preferredSummaryCamera = camera
    }

    func captureSnapshot() -> UIImage? {
        captureSnapshotFromCurrentCamera(hideSymbolLayers: true)
    }

    func captureSummarySnapshot() async -> UIImage? {
        guard let mapView,
              mapView.bounds.width > 0,
              mapView.bounds.height > 0 else {
            return nil
        }

        guard let preferredSummaryCamera else {
            return await captureSnapshotFromCurrentCameraAfterSettling()
        }

        mapView.camera.fly(
            to: preferredSummaryCamera,
            duration: Self.summaryFlyDuration
        )

        let flyDurationNanoseconds = UInt64((Self.summaryFlyDuration * 1_000_000_000).rounded())
        try? await Task.sleep(nanoseconds: flyDurationNanoseconds + Self.summarySettleDelayNanoseconds)

        return await captureSnapshotFromCurrentCameraAfterSettling()
    }

    private func captureSnapshotFromCurrentCameraAfterSettling() async -> UIImage? {
        guard let mapView else { return nil }

        let hiddenLayerStates = temporarilyHideSymbolLayers(on: mapView.mapboxMap)
        defer { restoreSymbolLayers(hiddenLayerStates, on: mapView.mapboxMap) }

        if !hiddenLayerStates.isEmpty {
            mapView.setNeedsLayout()
            mapView.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: Self.privacyHideSettleDelayNanoseconds)
        }

        return captureSnapshotFromCurrentCamera(hideSymbolLayers: false)
    }

    private func captureSnapshotFromCurrentCamera(hideSymbolLayers: Bool) -> UIImage? {
        guard let mapView,
              mapView.bounds.width > 0,
              mapView.bounds.height > 0 else {
            return nil
        }

        let hiddenLayerStates = hideSymbolLayers ? temporarilyHideSymbolLayers(on: mapView.mapboxMap) : []
        defer {
            if !hiddenLayerStates.isEmpty {
                restoreSymbolLayers(hiddenLayerStates, on: mapView.mapboxMap)
            }
        }

        mapView.setNeedsLayout()
        mapView.layoutIfNeeded()
        do {
            return try mapView.snapshot(includeOverlays: false)
        } catch {
            print("⚠️ [LiveCampaignMapSnapshotStore] Failed to capture live map snapshot: \(error)")
            return nil
        }
    }

    private func temporarilyHideSymbolLayers(on map: MapboxMap) -> [SymbolLayerVisibilityState] {
        let symbolLayerIds = map.allLayerIdentifiers
            .filter { $0.type == .symbol }
            .map(\.id)

        guard !symbolLayerIds.isEmpty else { return [] }

        var states: [SymbolLayerVisibilityState] = []
        states.reserveCapacity(symbolLayerIds.count)

        for id in symbolLayerIds {
            let originalVisibility = map.layerPropertyValue(for: id, property: "visibility")
            do {
                try map.setLayerProperty(for: id, property: "visibility", value: "none")
                states.append(SymbolLayerVisibilityState(id: id, visibility: originalVisibility))
            } catch {
                print("⚠️ [LiveCampaignMapSnapshotStore] Could not hide symbol layer \(id): \(error)")
            }
        }

        return states
    }

    private func restoreSymbolLayers(_ states: [SymbolLayerVisibilityState], on map: MapboxMap) {
        guard !states.isEmpty else { return }

        for state in states {
            do {
                try map.setLayerProperty(for: state.id, property: "visibility", value: state.visibility)
            } catch {
                print("⚠️ [LiveCampaignMapSnapshotStore] Could not restore symbol layer \(state.id): \(error)")
            }
        }
    }
}

private struct SymbolLayerVisibilityState {
    let id: String
    let visibility: Any
}
