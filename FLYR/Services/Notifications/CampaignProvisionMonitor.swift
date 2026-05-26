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

    func track(campaign: CampaignV2, state: CampaignProvisionBadgeState = .queued, statusText: String = "Campaign setup is queued.") {
        tracked = TrackedCampaignProvision(
            campaignId: campaign.id,
            campaignName: campaign.name,
            state: state,
            statusText: statusText
        )
        persist()
    }

    func update(campaignId: UUID, campaignName: String? = nil, state: CampaignProvisionBadgeState, statusText: String) {
        guard tracked?.campaignId == campaignId else { return }
        if let campaignName, !campaignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tracked?.campaignName = campaignName
        }
        tracked?.state = state
        tracked?.statusText = statusText
        persist()
    }

    func dismiss() {
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
                statusText: Self.statusText(status: state.provisionStatus, phase: state.provisionPhase)
            )
        } catch {
            #if DEBUG
            print("⚠️ [CampaignProvisionMonitor] Refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    static func badgeState(status: CampaignProvisionStatus?, phase: CampaignProvisionPhase?) -> CampaignProvisionBadgeState {
        if status == .failed || phase == .failed {
            return .needsAttention
        }
        if status == .ready && phase?.isLinkComplete == true {
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

    static func statusText(status: CampaignProvisionStatus?, phase: CampaignProvisionPhase?) -> String {
        if status == .failed || phase == .failed {
            return "Setup needs attention. Open the campaign to retry."
        }
        if status == .ready && phase?.isLinkComplete == true {
            return "Campaign is ready."
        }
        switch phase {
        case .sourceProbed, .addressesLoading, .addressesReady:
            return "Preparing homes and map data."
        case .mapReady, .optimizing:
            return "Optimizing homes and building links."
        case .created:
            return "Campaign setup is queued."
        default:
            return "Campaign setup is running in the background."
        }
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
