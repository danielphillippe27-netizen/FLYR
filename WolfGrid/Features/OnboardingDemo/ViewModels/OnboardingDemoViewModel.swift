import Foundation
import Combine

enum OnboardingDemoFeature {
    static let isEnabled = false
}

@MainActor
final class OnboardingDemoViewModel: ObservableObject {
    static let shared = OnboardingDemoViewModel()

    @Published private(set) var state: OnboardingDemoState?
    @Published private(set) var isLoading = false
    @Published private(set) var isSeeding = false
    @Published var errorMessage: String?

    private let api: OnboardingDemoAPI

    init(api: OnboardingDemoAPI = .shared) {
        self.api = api
    }

    var shouldShowPanel: Bool {
        guard OnboardingDemoFeature.isEnabled else { return false }
        guard let state else { return false }
        return !state.isDismissed
    }

    var checklistItems: [OnboardingDemoChecklistItem] {
        guard OnboardingDemoFeature.isEnabled else { return [] }
        guard let state else { return [] }
        return OnboardingDemoChecklistItem.items(for: state)
    }

    var completedItemIDs: Set<String> {
        Set(state?.completedChecklistItems ?? [])
    }

    func load() async {
        guard OnboardingDemoFeature.isEnabled else {
            state = nil
            errorMessage = nil
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            state = try await api.fetchState()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seedStarterCampaign(refreshCampaigns: Bool = true) async -> UUID? {
        guard OnboardingDemoFeature.isEnabled else {
            state = nil
            errorMessage = nil
            return nil
        }
        guard !isSeeding else { return state?.seededCampaignId }
        isSeeding = true
        defer { isSeeding = false }
        do {
            let response = try await api.seed()
            state = response.state
            errorMessage = nil
            if refreshCampaigns {
                await refreshCampaignStore()
            }
            return response.campaignId ?? response.state.seededCampaignId
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func dismiss() async {
        guard OnboardingDemoFeature.isEnabled else { return }
        do {
            state = try await api.patch(dismissed: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markComplete(_ id: String) async {
        guard OnboardingDemoFeature.isEnabled else { return }
        guard var current = state?.completedChecklistItems else { return }
        guard !current.contains(id) else { return }
        current.append(id)
        do {
            state = try await api.patch(completedChecklistItems: current)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markComplete(for action: OnboardingDemoAction) async {
        guard let item = checklistItems.first(where: { $0.action == action }) else { return }
        await markComplete(item.id)
    }

    private func refreshCampaignStore() async {
        do {
            let campaigns = try await CampaignsAPI.shared.fetchCampaignsV2(workspaceId: WorkspaceContext.shared.workspaceId)
            CampaignV2Store.shared.set(campaigns)
        } catch {
            print("⚠️ [OnboardingDemo] Failed to refresh campaigns after seed: \(error.localizedDescription)")
        }
    }
}
