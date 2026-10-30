import XCTest
import CoreLocation
import Combine
import SwiftUI
import UIKit
@testable import WolfGrid

@MainActor
final class DemoSessionSimulatorTests: XCTestCase {
    private func steps(_ count: Int) -> [DemoSessionStep] {
        (0..<count).map { index in
            let coordinate = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38 + Double(index) * 0.0001)
            let target = ResolvedCampaignTarget(id: "demo-\(index)", label: "\(index + 1) Test Street", coordinate: coordinate,
                addressId: nil, buildingId: nil, houseNumber: String(index + 1), streetName: "Test Street")
            return DemoSessionStep(target: target, travelPath: [coordinate])
        }
    }

    func testDemoSessionSurvivesTimerAndProducesSummary() async throws {
        let manager = SessionManager.shared
        XCTAssertNil(manager.sessionId)
        let route = steps(3)
        manager.startDemoBuildingSession(campaignId: UUID(), targetBuildings: route.map { $0.target.id },
            centroids: Dictionary(uniqueKeysWithValues: route.map { ($0.target.id, $0.target.coordinate) }),
            initialLocation: route.first?.target.coordinate)
        let sessionID = manager.sessionId
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(manager.sessionId, sessionID)
        XCTAssertTrue(manager.isDemoSession)
        for step in route {
            await manager.injectDemoLocation(step.target.coordinate)
            try await manager.completeBuilding(step.target.id)
            manager.recordAddressDelivered()
        }
        XCTAssertEqual(manager.completedCount, 3)
        let summaryReady = expectation(description: "summary published on the next UI turn")
        let observation = manager.$pendingSessionSummary.compactMap { $0 }.first().sink { _ in summaryReady.fulfill() }
        await manager.stopBuildingSession(presentSummary: true)
        await fulfillment(of: [summaryReady], timeout: 3)
        withExtendedLifetime(observation) {}
        XCTAssertNil(manager.sessionId)
        XCTAssertEqual(manager.pendingSessionSummary?.completedCount, 3)
        XCTAssertEqual(manager.pendingSessionSummary?.isDemoSession, true)
        manager.pendingSessionSummary = nil
        manager.pendingSessionSummarySessionId = nil
    }

    func testPlaybackAdvancesRealSessionTimerAndHomes() async throws {
        let manager = SessionManager.shared
        let simulator = DemoSessionSimulator()
        let route = steps(3)
        manager.startDemoBuildingSession(campaignId: UUID(), targetBuildings: route.map { $0.target.id },
            centroids: Dictionary(uniqueKeysWithValues: route.map { ($0.target.id, $0.target.coordinate) }),
            initialLocation: route.first?.target.coordinate)
        let finished = expectation(description: "playback completes real demo session")
        simulator.start(steps: route, speed: .medium, pathMode: .continuous, initialCoordinate: nil,
            onTargetWillAdvance: { _ in },
            onLocationUpdate: { coordinate, append in await manager.injectDemoLocation(coordinate, appendToTrail: append) },
            onTargetHit: { target in
                manager.markDemoCompletionFast(targetId: target.id, addressIds: [], buildingId: target.id,
                    coordinate: target.coordinate, status: .delivered)
            },
            onFinish: { reason in
                if case .completed = reason { finished.fulfill() }
                else { XCTFail("Playback unexpectedly stopped") }
            })
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertTrue(simulator.isRunning)
        XCTAssertGreaterThan(manager.elapsedTime, 0)
        XCTAssertGreaterThan(manager.completedCount, 0)
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(manager.completedCount, 3)
        await manager.stopBuildingSession(presentSummary: false)
    }

    func testZCachedCampaignMapStartsPlaybackWithoutNewLoadEvent() async throws {
        let campaignID = UUID()
        var campaignJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CampaignV2.mockCampaigns[0])) as! [String: Any]
        campaignJSON["id"] = campaignID.uuidString
        campaignJSON["name"] = "Cached demo startup test"
        campaignJSON["totalFlyers"] = 3
        campaignJSON["addresses"] = []
        let campaign = try JSONDecoder().decode(CampaignV2.self, from: JSONSerialization.data(withJSONObject: campaignJSON))
        var features: [[String: Any]] = []
        for index in 0..<735 {
            let longitude = -79.38 + Double(index) * 0.0001
            let geometry: [String: Any] = ["type": "Point", "coordinates": [longitude, 43.65]]
            let properties: [String: Any] = ["formatted": "\(index + 1) Test Street", "house_number": String(index + 1), "street_name": "Test Street"]
            let feature: [String: Any] = ["type": "Feature", "id": UUID().uuidString, "geometry": geometry, "properties": properties]
            features.append(feature)
        }
        // Match the reported large-campaign shape: hundreds of unlinked buildings
        // must not trigger a whole-campaign overlay replay for each simulated hit.
        var buildings: [[String: Any]] = []
        for index in 0..<825 {
            let lon = -79.38 + Double(index % 30) * 0.00025
            let lat = 43.65 + Double(index / 30) * 0.00025
            let ring: [[Double]] = [[lon, lat], [lon + 0.00015, lat], [lon + 0.00015, lat + 0.00015], [lon, lat + 0.00015], [lon, lat]]
            let geometry: [String: Any] = ["type": "Polygon", "coordinates": [ring]]
            let properties: [String: Any] = ["id": "fixture-building-\(index)", "height": 8, "area_sqm": 150, "house_number": String(index + 1), "street_name": "Test Street", "feature_type": "matched_house"]
            buildings.append(["type": "Feature", "id": "fixture-building-\(index)", "geometry": geometry, "properties": properties])
        }
        let empty: [String: Any] = ["type": "FeatureCollection", "features": []]
        let json: [String: Any] = [
            "campaign_id": campaignID.uuidString, "asset_signature": "demo-startup-test", "source_version": "test",
            "display_mode_hint": "buildings", "links_status": "ready",
            "addresses": ["type": "FeatureCollection", "features": features],
            "buildings": ["type": "FeatureCollection", "features": buildings], "parcels": empty, "roads": empty, "links": [],
            "expires_at": "2099-01-01T00:00:00Z"
        ]
        let bundle = try JSONDecoder().decode(CanonicalCampaignMapBundle.self, from: JSONSerialization.data(withJSONObject: json))
        let saved = await CampaignRepository.shared.replaceCampaignMapBundle(campaignId: campaignID.uuidString, bundle: bundle)
        XCTAssertTrue(saved)
        await CampaignRoadDeviceCache.shared.store(corridors: [], campaignId: campaignID.uuidString, version: 1)
        await MapFeaturesService.shared.fetchAllCampaignFeatures(campaignId: campaignID.uuidString)
        XCTAssertTrue(MapFeaturesService.shared.hasUsableCampaignData(campaignId: campaignID.uuidString))
        let configuration = DemoSessionLaunchConfiguration(campaign: campaign, homeCount: 20, speed: .slow,
            pathMode: .continuous, recordingViewStyle: .creatorOverlay, cameraAngle: .normal3D, hitPattern: .allGreen)
        let host = UIHostingController(rootView: CampaignMapView(campaignId: campaignID.uuidString,
            showPreSessionStartButton: false, demoLaunchConfiguration: configuration)
            .environmentObject(AppUIState()))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let manager = SessionManager.shared
        let deadline = Date().addingTimeInterval(8)
        while manager.sessionId == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(manager.isDemoSession, "A warm map must start the demo without waiting for another feature-load event")
        if manager.isDemoSession {
            let playbackCheckStarted = Date()
            try await Task.sleep(for: .milliseconds(5000))
            XCTAssertLessThan(Date().timeIntervalSince(playbackCheckStarted), 9, "Map rendering must not starve the playback task")
            XCTAssertGreaterThanOrEqual(manager.completedCount, 2, "Playback must continue past its first home")
            XCTAssertGreaterThanOrEqual(manager.elapsedTime, 3)
            let screenshot = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "Cached campaign demo advancing"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        window.isHidden = true
        window.rootViewController = nil
        if manager.isDemoSession { await manager.stopBuildingSession(presentSummary: false) }
    }

    func testContinuousSinglePointStepsRemainPacedAndComplete() async throws {
        let simulator = DemoSessionSimulator()
        let finished = expectation(description: "demo completes")
        var hits = 0
        let started = Date()
        simulator.start(steps: steps(3), speed: .fast, pathMode: .continuous, initialCoordinate: nil,
            onTargetWillAdvance: { _ in }, onLocationUpdate: { _, _ in }, onTargetHit: { _ in hits += 1 },
            onFinish: { reason in
                if case .completed = reason { finished.fulfill() }
                else { XCTFail("Unexpected stop") }
            })
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(simulator.isRunning)
        XCTAssertEqual(hits, 0)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(hits, 3)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.3)
        XCTAssertFalse(simulator.isRunning)
    }

    func testRestartDoesNotDeliverCancelledRunsStopCallback() async throws {
        let simulator = DemoSessionSimulator()
        simulator.start(steps: steps(3), speed: .slow, pathMode: .pauseAtHomes, initialCoordinate: nil,
            onTargetWillAdvance: { _ in }, onLocationUpdate: { _, _ in }, onTargetHit: { _ in },
            onFinish: { _ in XCTFail("Cancelled run must not finish into its replacement") })
        try await Task.sleep(for: .milliseconds(20))
        let finished = expectation(description: "replacement completes")
        simulator.start(steps: steps(3), speed: .fast, pathMode: .continuous, initialCoordinate: nil,
            onTargetWillAdvance: { _ in }, onLocationUpdate: { _, _ in }, onTargetHit: { _ in },
            onFinish: { reason in
                if case .completed = reason { finished.fulfill() }
                else { XCTFail("Replacement stopped unexpectedly") }
            })
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(simulator.isRunning)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertFalse(simulator.isRunning)
    }

    func testStreetSweepHitsEveryHomeAndSilentStopDoesNotFinish() async throws {
        let simulator = DemoSessionSimulator()
        let finished = expectation(description: "street sweep completes")
        var hits = Set<String>()
        simulator.startStreetSegmentSweep(steps: steps(4), speed: .fast,
            onSegmentWillAdvance: { _ in }, onLocationUpdate: { _, _ in },
            onTargetsHit: { targets in targets.forEach { hits.insert($0.id) } },
            onFinish: { reason in
                if case .completed = reason { finished.fulfill() }
                else { XCTFail("Street sweep stopped unexpectedly") }
            })
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(hits.count, 4)
        simulator.start(steps: steps(3), speed: .slow, pathMode: .continuous, initialCoordinate: nil,
            onTargetWillAdvance: { _ in }, onLocationUpdate: { _, _ in }, onTargetHit: { _ in },
            onFinish: { _ in XCTFail("Silent stop must not call finish") })
        try await Task.sleep(for: .milliseconds(20))
        simulator.stop(notify: false)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(simulator.isRunning)
    }
}
