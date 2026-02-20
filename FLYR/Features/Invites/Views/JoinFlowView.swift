import SwiftUI

/// Join flow: validate token, show workspace/email, sign-in or accept, then route by access state.
struct JoinFlowView: View {
    let token: String
    @EnvironmentObject var routeState: AppRouteState
    @EnvironmentObject var uiState: AppUIState
    @StateObject private var viewModel = JoinFlowViewModel()

    var body: some View {
        JoinFlowContent(
            token: token,
            viewModel: viewModel,
            onAcceptSuccess: {
                Task { await routeState.acceptPendingInviteAndResolve() }
            },
            onDismiss: {
                routeState.clearPendingJoinToken()
                Task { await routeState.resolveRoute() }
            }
        )
        .environmentObject(routeState)
        .preferredColorScheme(uiState.colorScheme)
    }
}
