//
//  FLYRTests.swift
//  FLYRTests
//
//  Created by Daniel Phillippe on 2025-10-20.
//

import Foundation
import Testing
@testable import FLYR

struct FLYRTests {

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
        #expect(GoalType.goalPickerCases(for: .doorKnocking) == [.knocks, .conversations, .appointments])
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

}
