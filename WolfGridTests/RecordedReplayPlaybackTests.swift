import XCTest
import CoreLocation
@testable import WolfGrid

@MainActor
final class RecordedReplayPlaybackTests: XCTestCase {
    func testPlaybackEmitsGPSAndVisitsInRecordedOrderAndStops() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let address = UUID()
        let points = [
            RecordedReplayPoint(coordinate: .init(latitude: 43, longitude: -79), timestamp: start),
            RecordedReplayPoint(coordinate: .init(latitude: 43.01, longitude: -79), timestamp: start.addingTimeInterval(10))
        ]
        let visits = [
            RecordedReplayVisit(timestamp: start, addressID: address, buildingID: nil, status: "talked"),
            RecordedReplayVisit(timestamp: start.addingTimeInterval(0.1), addressID: address, buildingID: nil, status: "delivered")
        ]
        let timeline = try XCTUnwrap(RecordedReplayTimeline(points: points, visits: visits))
        let simulator = DemoSessionSimulator()
        let received = expectation(description: "recorded outcomes emitted")
        var statuses: [String] = []
        var locationUpdates = 0
        simulator.startRecorded(timeline: timeline, speed: .fast, onLocation: { _, _ in
            locationUpdates += 1
        }, onVisit: { visit in
            statuses.append(visit.status)
            if statuses.count == 2 { received.fulfill() }
        }, onFinish: { _ in })
        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual(statuses, ["talked", "delivered"])
        XCTAssertGreaterThan(locationUpdates, 0)
        simulator.stop(notify: false)
        XCTAssertFalse(simulator.isRunning)
    }
}
