//
//  WolfGridTests.swift
//  WolfGridTests
//
//  Created by Daniel Phillippe on 2025-10-20.
//

import Foundation
import Testing
@testable import WolfGrid

struct WolfGridTests {

    @Test func campaignHouseCountUsesAggregateBeforeAddressHydration() throws {
        var campaign = CampaignV2(
            name: "Count test",
            type: .doorKnock,
            addressSource: .closestHome,
            addresses: [],
            totalFlyers: 17
        )

        #expect(campaign.houseCount == 17)

        campaign.addresses = (1...20).map { CampaignAddress(address: "\($0) Main St") }
        #expect(campaign.houseCount == 20)
    }

    @Test func offlinePreloadSelectorPrioritizesAssignedFarmAndRecentCampaigns() throws {
        let assigned = UUID()
        let farm = UUID()
        let recent = UUID()
        let duplicate = UUID()

        let candidates = OfflinePreloadSelector.selectCandidates(
            assignedCampaignIds: [assigned, duplicate],
            recentCampaignIds: [recent, duplicate],
            inProgressFarmCampaignIds: [farm]
        )

        #expect(candidates.map(\.campaignId) == [assigned, duplicate, farm, recent])
        #expect(candidates.map(\.reason) == ["assigned_route", "assigned_route", "in_progress_farm", "recent_campaign"])
        #expect(candidates.map(\.priority) == [300, 300, 200, 100])
    }

    @Test func diamondManifestDecodesSeparateWinnipegTileTemplates() throws {
        let json = """
        {
          "campaign_id": "fc1c992b-c0b4-48c0-9116-3c9e002196fd",
          "diamond_mode": true,
          "geometry_provider": "pmtiles",
          "geometry_version": 1777777777,
          "geometry_url": "https://example.test/buildings.pmtiles",
          "geometry_etag": "winnipeg-test",
          "tilejson_url": "https://example.test/buildings.json",
          "vector_tile_url_template": "https://example.test/diamond-tiles/buildings/{z}/{x}/{y}.mvt",
          "address_vector_tile_url_template": "https://example.test/address-tiles/{z}/{x}/{y}.mvt",
          "address_source_layer": "addresses",
          "address_promote_id": "address_id",
          "address_minzoom": 10,
          "address_maxzoom": 16,
          "parcel_vector_tile_url_template": "https://example.test/parcel-tiles/{z}/{x}/{y}.mvt",
          "parcel_source_layer": "parcels",
          "parcel_promote_id": "parcel_id",
          "parcel_minzoom": 10,
          "parcel_maxzoom": 16,
          "source_layers": {
            "buildings": "buildings",
            "addresses": "addresses",
            "address_circles": null,
            "parcels": "parcels"
          },
          "promote_ids": {
            "buildings": "address_id",
            "addresses": "address_id",
            "address_circles": null,
            "parcels": "parcel_id"
          },
          "join_key": "address_id",
          "primary_state_layer": "buildings",
          "bounds": [-97.35, 49.71, -96.95, 50.02],
          "minzoom": 13,
          "maxzoom": 18,
          "state_source": "supabase",
          "state_cursor": "2026-05-06T23:15:34Z",
          "supports_feature_state": true,
          "supports_differential_state_sync": true,
          "supports_rep_scope": true,
          "fallback_geometry_provider": null
        }
        """

        let manifest = try JSONDecoder().decode(DiamondManifest.self, from: Data(json.utf8))

        #expect(manifest.hasRenderablePMTilesGeometry)
        #expect(manifest.hasRenderablePMTilesAddresses)
        #expect(manifest.addressVectorTileUrlTemplate?.contains("address-tiles") == true)
        #expect(manifest.parcelVectorTileUrlTemplate?.contains("parcel-tiles") == true)
        #expect(manifest.addressSourceLayer == "addresses")
        #expect(manifest.parcelSourceLayer == "parcels")
    }

    @Test func beaconHeartbeatDeviceStatusEncodesAsJSON() throws {
        let timestamp = Date(timeIntervalSince1970: 1_712_734_400)
        let payload: [String: AnyCodable] = [
            "device_status": AnyCodable([
                "horizontal_accuracy": AnyCodable(8.5),
                "speed": AnyCodable(-1.0),
                "timestamp": AnyCodable(timestamp),
            ])
        ]

        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let deviceStatus = try #require(object["device_status"] as? [String: Any])

        #expect(deviceStatus["horizontal_accuracy"] as? Double == 8.5)
        #expect(deviceStatus["speed"] as? Double == -1.0)
        #expect(deviceStatus["timestamp"] as? String != nil)
    }

    @Test func doorKnockGoalPickerCasesMatchNewSessionStartFlow() async throws {
        #expect(GoalType.goalPickerCases(for: .doorKnocking) == [.knocks, .conversations, .appointments, .time])
    }

    @Test func doorKnockSessionsDefaultToAllCampaignHomes() async throws {
        #expect(GoalType.knocks.defaultAmount(for: .doorKnocking, targetCount: 120) == 120)
    }

    @Test func flyerSessionsDefaultToTimeGoals() async throws {
        #expect(SessionMode.flyer.defaultGoalType == .time)
        #expect(GoalType.time.defaultAmount(for: .flyer, targetCount: 120) == 60)
    }

    @Test func doorKnockProgressUsesDoorLanguage() async throws {
        #expect(GoalType.knocks.progressMetricLabel == "doors")
        #expect(GoalType.conversations.progressMetricLabel == "conversations")
    }

    @Test func campaignProvisionMonitorClampsProgress() async throws {
        #expect(CampaignProvisionMonitor.clampedProgress(-20) == 0)
        #expect(CampaignProvisionMonitor.clampedProgress(35) == 35)
        #expect(CampaignProvisionMonitor.clampedProgress(140) == 100)
    }

    @Test func campaignProvisionMonitorActivityTextMatchesProvisionPhase() async throws {
        #expect(CampaignProvisionMonitor.activityText(status: .pending, phase: .created) == "Creating campaign")
        #expect(CampaignProvisionMonitor.activityText(status: .pending, phase: .sourceProbed) == "Finding homes")
        #expect(CampaignProvisionMonitor.activityText(status: .pending, phase: .addressesLoading) == "Saving addresses")
        #expect(CampaignProvisionMonitor.activityText(status: .pending, phase: .mapReady) == "Preparing map")
        #expect(CampaignProvisionMonitor.activityText(status: .ready, phase: .linked) == "Campaign is ready")
    }

    @Test func campaignDetailProgressPrefersRealDoorSignalsOverLegacyProgress() async throws {
        let campaign = CampaignV2(
            id: UUID(),
            name: "Campaign",
            type: .doorKnock,
            addressSource: .closestHome,
            addresses: (1...30).map { CampaignAddress(address: "\($0) Main St") },
            totalFlyers: 30,
            scans: 30,
            conversions: 0,
            createdAt: Date()
        )
        let session = SessionRecord(
            id: UUID(),
            user_id: UUID(),
            start_time: Date(),
            end_time: Date().addingTimeInterval(600),
            doors_hit: 1,
            distance_meters: nil,
            conversations: 0,
            session_mode: nil,
            goal_type: nil,
            goal_amount: nil,
            path_geojson: nil,
            path_geojson_normalized: nil,
            active_seconds: nil,
            created_at: nil,
            updated_at: nil,
            campaign_id: campaign.id,
            farm_id: nil,
            farm_touch_id: nil,
            route_assignment_id: nil,
            target_building_ids: nil,
            completed_count: nil,
            flyers_delivered: nil,
            is_paused: nil,
            auto_complete_enabled: nil,
            notes: nil,
            doors_per_hour: nil,
            conversations_per_hour: nil,
            completions_per_km: nil,
            appointments_count: nil,
            appointments_per_conversation: nil,
            leads_created: nil,
            conversations_per_door: nil,
            leads_per_conversation: nil
        )

        let presentation = CampaignDetailPresentation(
            campaign: campaign,
            sessions: [session],
            fieldLeads: [],
            addressStatuses: [:]
        )

        #expect(presentation.doorsHit == 1)
        #expect(presentation.progressPercent == 3)
        #expect(abs(presentation.progressValue - (1.0 / 30.0)) < 0.0001)
    }

    @Test func campaignDetailProgressFallsBackToLegacyProgressWithoutDoorSignals() async throws {
        let campaign = CampaignV2(
            id: UUID(),
            name: "Campaign",
            type: .doorKnock,
            addressSource: .closestHome,
            addresses: (1...30).map { CampaignAddress(address: "\($0) Main St") },
            totalFlyers: 30,
            scans: 15,
            conversions: 0,
            createdAt: Date()
        )

        let presentation = CampaignDetailPresentation(
            campaign: campaign,
            sessions: [],
            fieldLeads: [],
            addressStatuses: [:]
        )

        #expect(presentation.doorsHit == 0)
        #expect(presentation.progressPercent == 50)
        #expect(abs(presentation.progressValue - 0.5) < 0.0001)
    }

    @Test func justSoldLivingCourtPresentationCompletesAllDoors() async throws {
        let campaign = CampaignV2(
            id: UUID(),
            name: "Just Sold - Living Court",
            type: .doorKnock,
            addressSource: .closestHome,
            addresses: (1...165).map { CampaignAddress(address: "\($0) Living Court") },
            totalFlyers: 165,
            scans: 0,
            conversions: 0,
            createdAt: Date()
        )
        let session = SessionRecord(
            id: UUID(),
            user_id: UUID(),
            start_time: Date(),
            end_time: Date().addingTimeInterval(240),
            doors_hit: 4,
            distance_meters: 100,
            conversations: 2,
            session_mode: nil,
            goal_type: nil,
            goal_amount: nil,
            path_geojson: nil,
            path_geojson_normalized: nil,
            active_seconds: nil,
            created_at: nil,
            updated_at: nil,
            campaign_id: campaign.id,
            farm_id: nil,
            farm_touch_id: nil,
            route_assignment_id: nil,
            target_building_ids: nil,
            completed_count: nil,
            flyers_delivered: nil,
            is_paused: nil,
            auto_complete_enabled: nil,
            notes: nil,
            doors_per_hour: nil,
            conversations_per_hour: nil,
            completions_per_km: nil,
            appointments_count: nil,
            appointments_per_conversation: nil,
            leads_created: nil,
            conversations_per_door: nil,
            leads_per_conversation: nil
        )

        let presentation = CampaignDetailPresentation(
            campaign: campaign,
            sessions: [session],
            fieldLeads: [],
            addressStatuses: [:]
        )

        #expect(presentation.totalDoors == 165)
        #expect(presentation.doorsHit == 165)
        #expect(presentation.progressPercent == 100)
        #expect(presentation.progressValue == 1.0)
        #expect(presentation.conversations == 57)
        #expect(presentation.leads == 12)
        #expect(presentation.syntheticLeads.count == 12)
        #expect(Set(presentation.syntheticLeads.compactMap(\.name)).count == 12)
    }

    @Test func livingCourtCompletionOverlayPreservesHotterStatuses() async throws {
        let addresses = (1...3).map { CampaignAddress(address: "\($0) Living Court") }
        let campaign = CampaignV2(
            id: UUID(),
            name: "Just Sold - Living Court",
            type: .doorKnock,
            addressSource: .closestHome,
            addresses: addresses,
            totalFlyers: addresses.count,
            scans: 0,
            conversions: 0,
            createdAt: Date()
        )

        let statuses = CampaignCompletionShowcase.completedAddressStatuses(
            for: campaign,
            overlaidOn: [addresses[0].id.uuidString: .hotLead]
        )

        #expect(statuses[addresses[0].id.uuidString] == .hotLead)
        #expect(statuses[addresses[1].id.uuidString] == .delivered)
        #expect(statuses[addresses[2].id.uuidString] == .delivered)
    }

    @Test func livingCourtMapOverlayUsesAssortedCompletedColorsWithTwoYellow() async throws {
        let addressIds = (1...24).map { _ in UUID() }

        let statuses = CampaignCompletionShowcase.assortedMapAddressStatuses(
            addressIds: addressIds,
            overlaidOn: [:]
        )

        let values = Array(statuses.values)
        #expect(values.contains(.noAnswer))
        #expect(values.contains(.delivered))
        #expect(values.contains(.hotLead))
        #expect(values.filter { $0 == .appointment }.count == 2)
    }

}
