import CoreLocation
import XCTest
@testable import WolfGrid

final class CampaignMapCameraPolicyTests: XCTestCase {
    func testLocationControlTapTransitionsThroughCenteredAndHeading3D() {
        XCTAssertEqual(
            CampaignMapCameraMode.idle.modeAfterLocationControlTap(hasLocation: true),
            .centered
        )
        XCTAssertEqual(
            CampaignMapCameraMode.centered.modeAfterLocationControlTap(hasLocation: true),
            .heading3D
        )
        XCTAssertEqual(
            CampaignMapCameraMode.heading3D.modeAfterLocationControlTap(hasLocation: true),
            .centered
        )
    }

    func testLocationControlTapDoesNotChangeModeWithoutLocation() {
        XCTAssertEqual(
            CampaignMapCameraMode.idle.modeAfterLocationControlTap(hasLocation: false),
            .idle
        )
        XCTAssertEqual(
            CampaignMapCameraMode.centered.modeAfterLocationControlTap(hasLocation: false),
            .centered
        )
    }

    func testFollowPolicyAlwaysUpdatesWithoutPreviousSnapshot() {
        let next = snapshot(latitude: 43.65, longitude: -79.38, heading: 90)
        XCTAssertTrue(CampaignMapFollowCameraPolicy.shouldUpdateCamera(from: nil, to: next))
    }

    func testFollowPolicySkipsTinyMovementAndHeadingChanges() {
        let previous = snapshot(latitude: 43.65, longitude: -79.38, heading: 90)
        let next = snapshot(latitude: 43.650005, longitude: -79.38, heading: 92)

        XCTAssertFalse(CampaignMapFollowCameraPolicy.shouldUpdateCamera(from: previous, to: next))
    }

    func testFollowPolicyUpdatesAfterMovementThreshold() {
        let previous = snapshot(latitude: 43.65, longitude: -79.38, heading: 90)
        let next = snapshot(latitude: 43.65002, longitude: -79.38, heading: 90)

        XCTAssertTrue(CampaignMapFollowCameraPolicy.shouldUpdateCamera(from: previous, to: next))
    }

    func testFollowPolicyUpdatesAfterHeadingThreshold() {
        let previous = snapshot(latitude: 43.65, longitude: -79.38, heading: 358)
        let next = snapshot(latitude: 43.65, longitude: -79.38, heading: 2)

        XCTAssertTrue(CampaignMapFollowCameraPolicy.shouldUpdateCamera(from: previous, to: next))
    }

    private func snapshot(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        heading: CLLocationDirection
    ) -> CampaignMapFollowCameraSnapshot {
        CampaignMapFollowCameraSnapshot(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            heading: heading
        )
    }
}
