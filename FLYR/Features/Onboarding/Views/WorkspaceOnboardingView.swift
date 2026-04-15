import SwiftUI
import Supabase

/// Workspace onboarding flow: name, use case, workspace name, industry, optional brokerage, optional invite emails. Submits via POST /api/onboarding/complete.
struct WorkspaceOnboardingView: View {
    @EnvironmentObject var routeState: AppRouteState
    @EnvironmentObject var uiState: AppUIState
    @EnvironmentObject var entitlementsService: EntitlementsService
    @StateObject private var viewModel = WorkspaceOnboardingViewModel()
    @State private var isSubmitting = false

    var body: some View {
        WorkspaceOnboardingContainerView(viewModel: viewModel) {
            Task {
                await submitAndNavigate()
            }
        }
        .environmentObject(routeState)
        .preferredColorScheme(uiState.colorScheme)
    }

    private func submitAndNavigate() async {
        guard !isSubmitting else { return }
        guard viewModel.canSubmit, let request = viewModel.buildRequest() else {
            viewModel.errorMessage = "Please complete all required fields before continuing."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        viewModel.errorMessage = nil

        // Complete onboarding on backend for both solo and team so web/app routing sees this user as onboarded.
        do {
            await ensureFreshSession()
            let response = try await AccessAPI.shared.completeOnboarding(request)
            _ = await entitlementsService.fetchEntitlement()
            await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
            await MainActor.run {
                advanceAfterSuccessfulOnboarding(response)
            }
        } catch {
            do {
                await ensureFreshSession()
                let response = try await AccessAPI.shared.completeOnboarding(request)
                _ = await entitlementsService.fetchEntitlement()
                await StoreKitManager.shared.refreshLocalProFromCurrentEntitlements()
                await MainActor.run {
                    advanceAfterSuccessfulOnboarding(response)
                }
                return
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func advanceAfterSuccessfulOnboarding(_ response: OnboardingCompleteResponse) {
        let normalizedRedirect = response.redirect?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedRedirect == "/subscribe" || normalizedRedirect == "subscribe" {
            routeState.setRouteToSubscribe(memberInactive: false)
            return
        }
        routeState.setRoute(.dashboard)
    }

    private func ensureFreshSession() async {
        let session = try? await SupabaseManager.shared.client.auth.refreshSession()
        if let session {
            KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
        }
    }
}
