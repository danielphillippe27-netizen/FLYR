import Foundation
#if !WOLFGRID_STANDALONE_MAP_TESTS
import XCTest
@testable import WolfGrid
#endif

final class StandardCampaignClusterLayoutTests: XCTestCase {
    private typealias Layout = StandardCampaignClusterLayout

    private func points(_ count: Int) -> [UUID: Layout.Point] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            (UUID(), Layout.Point(latitude: 43.65 + Double(index / 100) * 0.0002,
                                  longitude: -79.38 + Double(index % 100) * 0.0002))
        })
    }

    func testUnchangedDataAndFractionalZoomDoNotRebuild() throws {
        var layout = Layout()
        let homes = points(1_000)
        XCTAssertNotNil(layout.update(points: homes, zoom: 15))
        for step in 0..<100 {
            XCTAssertNil(layout.update(points: homes, zoom: 15 + Float(step) / 101))
        }
        XCTAssertEqual(layout.rebuildCount, 1)
        XCTAssertNotNil(layout.update(points: homes, zoom: 16))
        XCTAssertEqual(layout.rebuildCount, 2)
    }

    func testStatusOnlyUpdateDoesNotChangeGeometryPlan() throws {
        var layout = Layout()
        let homes = points(1_000)
        _ = layout.update(points: homes, zoom: 16)
        // Status/GPS/menu changes supply the same geometry dictionary to the renderer.
        let reordered = Dictionary(uniqueKeysWithValues: homes.reversed())
        XCTAssertNil(layout.update(points: reordered, zoom: 16))
        XCTAssertEqual(layout.rebuildCount, 1)
    }

    func testZoomGestureDefersChangesAndAppliesLatestDataAtIdle() throws {
        var layout = Layout()
        let homes = points(1_000)
        _ = layout.update(points: homes, zoom: 14)
        var edited = homes
        let movedID = try XCTUnwrap(homes.keys.first)
        edited[movedID] = .init(latitude: 44, longitude: -79)
        for step in 0..<120 {
            XCTAssertNil(layout.update(points: edited, zoom: 14 + Float(step) / 40, isMoving: true))
        }
        XCTAssertEqual(layout.rebuildCount, 1)
        let plan = try XCTUnwrap(layout.update(points: edited, zoom: 17))
        let ids = plan.individualIDs.union(plan.clusters.values.flatMap(\.keys))
        XCTAssertEqual(ids, Set(edited.keys))
        XCTAssertEqual(layout.rebuildCount, 2)
    }

    func testEveryHomeAppearsExactlyOnceAcrossAllZoomLevels() throws {
        var layout = Layout()
        let homes = points(1_000)
        for zoom in 0...22 {
            let result = layout.update(points: homes, zoom: Float(zoom))
            if zoom > 18 { XCTAssertNil(result); continue }
            let plan = try XCTUnwrap(result)
            let clustered = plan.clusters.values.flatMap(\.keys)
            XCTAssertEqual(clustered.count + plan.individualIDs.count, homes.count)
            XCTAssertEqual(Set(clustered).union(plan.individualIDs), Set(homes.keys))
            XCTAssertTrue(Set(clustered).isDisjoint(with: plan.individualIDs))
            XCTAssertTrue(plan.clusters.values.allSatisfy { $0.count > 1 })
            if zoom == 18 { XCTAssertEqual(plan.individualIDs, Set(homes.keys)) }
        }
    }

    func testAddMoveRemoveAndSameCountReplacementInvalidateLayout() throws {
        var layout = Layout()
        var homes = points(3)
        _ = layout.update(points: homes, zoom: 15)
        let id = try XCTUnwrap(homes.keys.first)
        homes[id] = .init(latitude: -43, longitude: 80)
        XCTAssertNotNil(layout.update(points: homes, zoom: 15))
        homes.removeValue(forKey: id)
        homes[UUID()] = .init(latitude: 44, longitude: -80)
        XCTAssertNotNil(layout.update(points: homes, zoom: 15))
        homes[UUID()] = .init(latitude: 45, longitude: -80)
        XCTAssertNotNil(layout.update(points: homes, zoom: 15))
        XCTAssertNotNil(layout.update(points: [:], zoom: 15))
        XCTAssertNil(layout.update(points: [:], zoom: 15))
        XCTAssertEqual(layout.rebuildCount, 5)
    }

    func testInvalidCoordinatesAndExtremeZoomNeverCrash() throws {
        var layout = Layout()
        let validID = UUID()
        let homes: [UUID: Layout.Point] = [
            validID: .init(latitude: 90, longitude: 180),
            UUID(): .init(latitude: .nan, longitude: 0),
            UUID(): .init(latitude: 0, longitude: .infinity),
            UUID(): .init(latitude: 91, longitude: 0),
            UUID(): .init(latitude: 0, longitude: -181)
        ]
        for zoom: Float in [-100, .nan, .infinity, 100] {
            if let plan = layout.update(points: homes, zoom: zoom) {
                XCTAssertEqual(plan.individualIDs.union(plan.clusters.values.flatMap(\.keys)), [validID])
            }
        }
    }

    func testTenThousandPinsDoNotReclusterDuringRepeatedViewUpdates() throws {
        var layout = Layout()
        let homes = points(10_000)
        let started = ProcessInfo.processInfo.systemUptime
        let first = try XCTUnwrap(layout.update(points: homes, zoom: 15))
        let firstMs = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let repeated = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { XCTAssertNil(layout.update(points: homes, zoom: 15.5)) }
        let repeatMs = (ProcessInfo.processInfo.systemUptime - repeated) * 1000
        XCTAssertEqual(layout.rebuildCount, 1)
        XCTAssertEqual(first.individualIDs.count + first.clusters.values.reduce(0) { $0 + $1.count }, homes.count)
        print(String(format: "2D BENCHMARK pins=10000 firstLayoutMs=%.2f unchanged100Ms=%.2f rebuilds=%d",
                     firstMs, repeatMs, layout.rebuildCount))
    }

    static var standaloneTests: [(String, (StandardCampaignClusterLayoutTests) -> () throws -> Void)] {
        [
            ("unchanged data and fractional zoom", testUnchangedDataAndFractionalZoomDoNotRebuild),
            ("status-only updates", testStatusOnlyUpdateDoesNotChangeGeometryPlan),
            ("gesture deferral", testZoomGestureDefersChangesAndAppliesLatestDataAtIdle),
            ("all homes at every zoom", testEveryHomeAppearsExactlyOnceAcrossAllZoomLevels),
            ("add move remove replace", testAddMoveRemoveAndSameCountReplacementInvalidateLayout),
            ("invalid coordinates and zoom", testInvalidCoordinatesAndExtremeZoomNeverCrash),
            ("10000-pin benchmark", testTenThousandPinsDoNotReclusterDuringRepeatedViewUpdates)
        ]
    }
}
