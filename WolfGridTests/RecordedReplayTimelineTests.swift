import XCTest
import CoreLocation
@testable import WolfGrid

final class RecordedReplayTimelineTests: XCTestCase {
    func testUsesRecordedTimeAndOrdersSamplesAndVisits() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let points = [
            RecordedReplayPoint(coordinate: .init(latitude: 44, longitude: -78), timestamp: start.addingTimeInterval(10)),
            RecordedReplayPoint(coordinate: .init(latitude: 43, longitude: -79), timestamp: start)
        ]
        let first = RecordedReplayVisit(timestamp: start.addingTimeInterval(2.5), addressID: UUID(), buildingID: nil, status: "talked")
        let last = RecordedReplayVisit(timestamp: start.addingTimeInterval(7.5), addressID: UUID(), buildingID: nil, status: "delivered")
        let timeline = try XCTUnwrap(RecordedReplayTimeline(points: points, visits: [last, first]))
        XCTAssertEqual(timeline.coordinate(at: 0.25).latitude, 43.25, accuracy: 0.00001)
        XCTAssertEqual(timeline.timeFraction(for: first), 0.25, accuracy: 0.00001)
        XCTAssertEqual(timeline.visits.first?.status, "talked")
    }

    func testHoldsEndLocationForOutlyingEventsAndCrossesDateLine() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let points = [
            RecordedReplayPoint(coordinate: .init(latitude: 0, longitude: 179), timestamp: start),
            RecordedReplayPoint(coordinate: .init(latitude: 0, longitude: -179), timestamp: start.addingTimeInterval(10))
        ]
        let visit = RecordedReplayVisit(timestamp: start.addingTimeInterval(20), addressID: UUID(), buildingID: nil, status: "talked")
        let timeline = try XCTUnwrap(RecordedReplayTimeline(points: points, visits: [visit]))
        XCTAssertEqual(abs(timeline.coordinate(at: 0.25).longitude), 180, accuracy: 0.00001)
        XCTAssertEqual(timeline.coordinate(at: 1).longitude, -179, accuracy: 0.00001)
        XCTAssertEqual(timeline.timeFraction(for: visit), 1, accuracy: 0.00001)
        XCTAssertNil(RecordedReplayTimeline(points: [points[0]], visits: [visit]))
    }
    func testPreservesInputOrderForSimultaneousOutcomes() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let points = [
            RecordedReplayPoint(coordinate: .init(latitude: 43, longitude: -79), timestamp: start),
            RecordedReplayPoint(coordinate: .init(latitude: 43.1, longitude: -79), timestamp: start.addingTimeInterval(10))
        ]
        let address = UUID()
        let first = RecordedReplayVisit(timestamp: start.addingTimeInterval(5), addressID: address, buildingID: nil, status: "talked")
        let second = RecordedReplayVisit(timestamp: start.addingTimeInterval(5), addressID: address, buildingID: nil, status: "none")
        let timeline = try XCTUnwrap(RecordedReplayTimeline(points: points, visits: [first, second]))
        XCTAssertEqual(timeline.visits.map(\.status), ["talked", "none"])
    }

    func testDoesNotInventMovementAcrossLongGPSGaps() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let points = [
            RecordedReplayPoint(coordinate: .init(latitude: 43, longitude: -79), timestamp: start),
            RecordedReplayPoint(coordinate: .init(latitude: 44, longitude: -78), timestamp: start.addingTimeInterval(120))
        ]
        let timeline = try XCTUnwrap(RecordedReplayTimeline(points: points, visits: []))
        XCTAssertEqual(timeline.coordinate(at: 0.5).latitude, 43, accuracy: 0.00001)
        XCTAssertEqual(timeline.coordinate(at: 1).latitude, 44, accuracy: 0.00001)
        XCTAssertEqual(timeline.gapEndFractions, [1])
    }

    func testRejectsConflictingLocationsAtTheSameTime() {
        let start = Date(timeIntervalSince1970: 1000)
        let points = [
            RecordedReplayPoint(coordinate: .init(latitude: 43, longitude: -79), timestamp: start),
            RecordedReplayPoint(coordinate: .init(latitude: 44, longitude: -79), timestamp: start),
            RecordedReplayPoint(coordinate: .init(latitude: 45, longitude: -79), timestamp: start.addingTimeInterval(10))
        ]
        XCTAssertNil(RecordedReplayTimeline(points: points, visits: []))
    }

}
