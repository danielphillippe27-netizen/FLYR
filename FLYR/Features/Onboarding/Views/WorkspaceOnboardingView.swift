import SwiftUI
import Supabase

/// Workspace onboarding flow: name, use case, workspace name, industry, optional brokerage, optional invite emails. Submits via POST /api/onboarding/complete.
struct WorkspaceOnboardingView: View {
    @EnvironmentObject var routeState: AppRouteState
    @EnvironmentObject var uiState: AppUIState
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
        isSubmitting = true
        defer { isSubmitting = false }

        // Solo: no backend; go straight to in-app paywall (Pay with Apple).
        if viewModel.useCase == .solo {
            await MainActor.run {
                routeState.setRouteToSubscribe(memberInactive: false)
            }
            return
        }

        // Team: call backend to complete onboarding, then always show paywall.
        guard let request = viewModel.buildRequest() else {
            await MainActor.run { routeState.setRouteToSubscribe(memberInactive: false) }
            return
        }
        do {
            await ensureFreshSession()
            _ = try await AccessAPI.shared.completeOnboarding(request)
            await MainActor.run {
                routeState.setRouteToSubscribe(memberInactive: false)
            }
        } catch {
            do {
                await ensureFreshSession()
                _ = try await AccessAPI.shared.completeOnboarding(request)
                await MainActor.run {
                    routeState.setRouteToSubscribe(memberInactive: false)
                }
                return
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                    routeState.setRouteToSubscribe(memberInactive: false)
                }
            }
        }
    }

    private func ensureFreshSession() async {
        let session = try? await SupabaseManager.shared.client.auth.refreshSession()
        if let session {
            KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
        }
    }
}
