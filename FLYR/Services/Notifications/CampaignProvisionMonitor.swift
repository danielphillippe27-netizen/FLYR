import Foundation
import Combine

enum CampaignProvisionBadgeState: String, Codable, Equatable {
    case queued
    case preparingMap
    case optimizing
    case ready
    case needsAttention
}

struct TrackedCampaignProvision: Codable, Equatable {
    let campaignId: UUID
    var campaignName: String
    var state: CampaignProvisionBadgeState
    var statusText: String
    var progressPercent: Int?

    var isRunning: Bool {
        state == .queued || state == .preparingMap || state == .optimizing
    }

    var displayProgressPercent: Int {
        CampaignProvisionMonitor.clampedProgress(progressPercent ?? 0)
    }

    var activityText: String {
        CampaignProvisionMonitor.activityText(state: state, progressPercent: progressPercent)
    }
}

@MainActor
final class CampaignProvisionMonitor: ObservableObject {
    static let shared = CampaignProvisionMonitor()

    @Published private(set) var tracked: TrackedCampaignProvision?

    private let storageKey = "latest_tracked_campaign_provision"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            tracked = try? JSONDecoder().decode(TrackedCampaignProvision.self, from: data)
        }
    }

    func track(
        campaign: CampaignV2,
        state: CampaignProvisionBadgeState = .queued,
        statusText: String = CampaignProvisionMonitor.runningStatusText,
        progressPercent: Int? = 0
    ) {
        let next = TrackedCampaignProvision(
            campaignId: campaign.id,
            campaignName: campaign.name,
            state: state,
            statusText: statusText,
            progressPercent: progressPercent
        )
        guard tracked != next else { return }
        tracked = next
        persist()
    }

    func update(
        campaignId: UUID,
        campaignName: String? = nil,
        state: CampaignProvisionBadgeState,
        statusText: String,
        progressPercent: Int? = nil
    ) {
        guard var next = tracked, next.campaignId == campaignId else { return }
        if let campaignName, !campaignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.campaignName = campaignName
        }
        next.state = state
        next.statusText = statusText
        if let progressPercent {
            next.progressPercent = Self.clampedProgress(progressPercent)
        }
        guard tracked != next else { return }
        tracked = next
        persist()
    }

    func dismiss(campaignId: UUID? = nil) {
        if let campaignId, tracked?.campaignId != campaignId {
            return
        }
        tracked = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func refreshLatest() async {
        guard let tracked else { return }
        do {
            let state = try await CampaignsAPI.shared.fetchProvisionState(campaignId: tracked.campaignId)
            update(
                campaignId: tracked.campaignId,
                state: Self.badgeState(status: state.provisionStatus, phase: state.provisionPhase),
                statusText: Self.statusText(status: state.provisionStatus, phase: state.provisionPhase),
                progressPercent: Self.progressPercent(status: state.provisionStatus, phase: state.provisionPhase)
            )
        } catch {
            #if DEBUG
            print("⚠️ [CampaignProvisionMonitor] Refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    nonisolated static let runningStatusText = "Campaign setup is running in the background."

    nonisolated static func badgeState(status: CampaignProvisionStatus?, phase: CampaignProvisionPhase?) -> CampaignProvisionBadgeState {
        if status == .failed || phase == .failed {
            return .needsAttention
        }
        if status == .ready && (phase?.isMapUsable ?? true) {
            return .ready
        }
        if phase == .mapReady || phase == .optimizing {
            return .optimizing
        }
        if phase == .addressesLoading || phase == .addressesReady || phase == .sourceProbed {
            return .preparingMap
        }
        return .queued
    }

    nonisolated static func statusText(status: CampaignProvisionStatus?, phase: CampaignProvisionPhase?) -> String {
        if status == .failed || phase == .failed {
            return "Setup needs attention. Open the campaign to retry."
        }
        if status == .ready && (phase?.isMapUsable ?? true) {
            return phase == .linkingFailed
                ? "Campaign is ready in standard map mode."
                : "Campaign is ready."
        }
        switch phase {
        case .sourceProbed, .addressesLoading, .addressesReady:
            return runningStatusText
        case .mapReady, .optimizing:
            return runningStatusText
        case .created:
            return runningStatusText
        default:
            return runningStatusText
        }
    }

    nonisolated static func activityText(status: CampaignProvisionStatus?, phase: CampaignProvisionPhase?) -> String {
        if status == .failed || phase == .failed {
            return "Setup needs attention"
        }
        if status == .ready && (phase?.isMapUsable ?? true) {
            return "Campaign is ready"
        }

        switch phase {
        case .created, .none:
            return "Creating campaign"
        case .sourceProbed:
            return "Finding homes"
        case .addressesLoading:
            return "Saving addresses"
        case .addressesReady, .mapReady:
            return "Preparing map"
        case .optimizing, .linked:
            return "Finalizing map"
        case .linkingFailed, .optimized:
            return "Campaign is ready"
        case .failed:
            return "Setup needs attention"
        }
    }

    nonisolated static func activityText(state: CampaignProvisionBadgeState, progressPercent: Int?) -> String {
        switch state {
        case .ready:
            return "Campaign is ready"
        case .needsAttention:
            return "Setup needs attention"
        case .queued, .preparingMap, .optimizing:
            return activityText(progressPercent: progressPercent)
        }
    }

    nonisolated static func activityText(progressPercent: Int?) -> String {
        let progressPercent = clampedProgress(progressPercent ?? 0)
        if progressPercent >= 100 {
            return "Campaign is ready"
        }
        if progressPercent >= 82 {
            return "Finalizing map"
        }
        if progressPercent >= 50 {
            return "Preparing map"
        }
        if progressPercent >= 35 {
            return "Saving addresses"
        }
        if progressPercent >= 18 {
            return "Finding homes"
        }
        return "Creating campaign"
    }

    nonisolated static func progressPercent(status: CampaignProvisionStatus?, phase: CampaignProvisionPhase?) -> Int? {
        if status == .failed || phase == .failed {
            return nil
        }
        if status == .ready && (phase?.isMapUsable ?? true) {
            return 100
        }
        switch phase {
        case .created:
            return 5
        case .sourceProbed:
            return 18
        case .addressesLoading:
            return 35
        case .addressesReady:
            return 50
        case .mapReady:
            return 68
        case .optimizing:
            return 82
        case .linkingFailed:
            return 100
        case .linked:
            return 95
        case .optimized:
            return 100
        case .failed:
            return nil
        case .none:
            return status == .pending ? 8 : 0
        }
    }

    nonisolated static func clampedProgress(_ progressPercent: Int) -> Int {
        min(max(progressPercent, 0), 100)
    }

    private func persist() {
        guard let tracked,
              let data = try? JSONEncoder().encode(tracked) else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
