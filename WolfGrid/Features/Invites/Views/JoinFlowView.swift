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
            onAcceptSuccess: { response in
                Task {
                    let resolvedCampaignId = response.campaignId ?? viewModel.validated?.campaignId
                    let resolvedCampaignTitle = viewModel.validated?.campaignTitle ?? viewModel.validated?.workspaceName
                    // Prefer the accepted live session id, but keep the validated live session
                    // as a fallback so "Join live" still routes into the session handoff when
                    // older backend rows fail to echo session_id back consistently.
                    let resolvedSessionId = response.sessionId ?? viewModel.validated?.sessionId

                    if let campaignId = resolvedCampaignId.flatMap(UUID.init(uuidString:)) {
                        if let sourceSessionId = resolvedSessionId.flatMap(UUID.init(uuidString:)) {
                            uiState.beginLiveInviteHandoff(
                                campaignId: campaignId,
                                name: resolvedCampaignTitle,
                                sourceSessionId: sourceSessionId
                            )
                        } else {
                            uiState.selectedTabIndex = 1
                            uiState.selectCampaign(id: campaignId, name: resolvedCampaignTitle)
                        }
                    }
                    let workspaceToAdopt =
                        response.accessScope == "workspace" && response.campaignId == nil
                        ? response.workspaceId
                        : nil
                    await routeState.completePendingJoinAndResolve(workspaceId: workspaceToAdopt)
                }
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
