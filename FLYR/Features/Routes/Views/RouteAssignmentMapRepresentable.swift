import SwiftUI

struct RouteAssignmentMapRepresentable: UIViewControllerRepresentable {
    let campaignId: UUID?
    let stops: [RoutePlanStop]
    let mode: RouteAssignmentMapDisplayMode

    func makeUIViewController(context: Context) -> RouteAssignmentMapViewController {
        let vc = RouteAssignmentMapViewController()
        vc.campaignId = campaignId
        vc.stops = stops
        vc.displayMode = mode
        return vc
    }

    func updateUIViewController(_ uiViewController: RouteAssignmentMapViewController, context: Context) {
        uiViewController.reload(stops: stops, campaignId: campaignId, mode: mode)
    }
}
