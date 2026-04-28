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
