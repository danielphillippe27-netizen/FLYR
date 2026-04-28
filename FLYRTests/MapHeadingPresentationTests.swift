import CoreLocation
import XCTest
@testable import FLYR

@MainActor
final class MapHeadingPresentationTests: XCTestCase {
    func testStableCompassAtRestUsesHeadingMode() {
        let engine = MapHeadingPresentationEngine()
        let now = Date()

        let firstState = engine.nextState(
            location: makeLocation(speed: 0.2, course: -1, timestamp: now),
            headingState: makeHeadingState(heading: 92, accuracy: 6),
            now: now
        )
        let secondState = engine.nextState(
            location: makeLocation(speed: 0.2, course: -1, timestamp: now.addingTimeInterval(0.5)),
            headingState: makeHeadingState(heading: 93, accuracy: 5),
            now: now.addingTimeInterval(0.5)
        )

        XCTAssertEqual(firstState.mode, .heading)
        XCTAssertEqual(secondState.mode, .heading)
        XCTAssertNotNil(secondState.heading)
        XCTAssertEqual(secondState.heading ?? 0, 92.28, accuracy: 1.0)
        XCTAssertGreaterThan(secondState.opacity, 0.1)
    }

    func testFastMovementPrefersCourseOverCompass() {
        let engine = MapHeadingPresentationEngine()
        let now = Date()

        _ = engine.nextState(
            location: makeLocation(speed: 0.3, course: -1, timestamp: now),
            headingState: makeHeadingState(heading: 90, accuracy: 6),
            now: now
        )

        let movingState = engine.nextState(
            location: makeLocation(speed: 2.1, course: 140, horizontalAccuracy: 8, timestamp: now.addingTimeInterval(0.6)),
            headingState: makeHeadingState(heading: 88, accuracy: 7),
            now: now.addingTimeInterval(0.6)
        )

        XCTAssertEqual(movingState.mode, .course)
        XCTAssertNotNil(movingState.heading)
        XCTAssertGreaterThan(movingState.heading ?? 0, 100)
        XCTAssertLessThan(movingState.spreadDegrees, 60)
        XCTAssertGreaterThan(movingState.opacity, 0.18)
    }

    func testBriefCompassLossFreezesBeforeGoingUnavailable() {
        let engine = MapHeadingPresentationEngine()
        let now = Date()

        let reliableState = engine.nextState(
            location: makeLocation(speed: 0.2, course: -1, timestamp: now),
            headingState: makeHeadingState(heading: 135, accuracy: 4),
            now: now
        )

        let frozenState = engine.nextState(
            location: makeLocation(speed: 0.2, course: -1, timestamp: now.addingTimeInterval(1.0)),
            headingState: .unavailable,
            now: now.addingTimeInterval(1.0)
        )

        let unavailableState = engine.nextState(
            location: makeLocation(speed: 0.2, course: -1, timestamp: now.addingTimeInterval(3.0)),
            headingState: .unavailable,
            now: now.addingTimeInterval(3.0)
        )

        XCTAssertEqual(frozenState.mode, .frozen)
        XCTAssertEqual(frozenState.heading ?? 0, reliableState.heading ?? 0, accuracy: 0.1)
        XCTAssertGreaterThan(frozenState.spreadDegrees, reliableState.spreadDegrees)
        XCTAssertLessThan(frozenState.opacity, reliableState.opacity)
        XCTAssertEqual(unavailableState.mode, .unavailable)
        XCTAssertNil(unavailableState.heading)
    }

    private func makeHeadingState(
        heading: CLLocationDirection,
        accuracy: CLLocationDirection
    ) -> MapHeadingState {
        MapHeadingState(
            heading: heading,
            accuracy: accuracy,
            source: .trueNorth
        )
    }

    private func makeLocation(
        speed: CLLocationSpeed,
        course: CLLocationDirection,
        horizontalAccuracy: CLLocationAccuracy = 8,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 5,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}
