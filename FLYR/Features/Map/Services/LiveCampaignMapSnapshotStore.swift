import UIKit
import MapboxMaps

@MainActor
final class LiveCampaignMapSnapshotStore {
    static let shared = LiveCampaignMapSnapshotStore()

    private init() {}

    weak var mapView: MapView?

    func setMapView(_ mapView: MapView?) {
        self.mapView = mapView
    }

    func captureSnapshot() -> UIImage? {
        guard let mapView,
              mapView.bounds.width > 0,
              mapView.bounds.height > 0 else {
            return nil
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
}
