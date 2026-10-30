import SwiftUI

/// The root experience for the private WolfGrid Sales app.
///
/// This intentionally has no dependency on the field-app campaign/session
/// navigation. Pro mode keeps the five daily sales workflows one tap away.
struct SalespersonMainTabView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.scenePhase) private var scenePhase
    @State private var visitedTabs: Set<Int> = [0]

    private enum Tab: Int {
        case home = 0
        case inbox = 1
        case contacts = 2
        case dialler = 3
        case followUp = 4
    }

    var body: some View {
        VStack(spacing: 0) {
            SharedActiveCallBanner()
            ZStack {
                ForEach(visitedTabs.sorted(), id: \.self) { index in
                    tabContent(index)
                        .opacity(uiState.selectedTabIndex == index ? 1 : 0)
                        .allowsHitTesting(uiState.selectedTabIndex == index)
                        .accessibilityHidden(uiState.selectedTabIndex != index)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if uiState.showTabBar {
                UberStyleTabBar(
                    selectedIndex: uiState.selectedTabIndex,
                    onSelect: { index in
                        HapticManager.tabSwitch()
                        visitedTabs.insert(index)
                        uiState.selectedTabIndex = index
                    },
                    onCreate: {},
                    recordHighlight: false,
                    accentColor: .red,
                    mode: .salesperson
                )
            }
        }
        .id("\(auth.user?.id.uuidString ?? "signed-out"):\(workspace.workspaceId?.uuidString ?? "no-workspace")")
        .background(Color.bg)
        .onAppear {
            normalizeSelectedTab()
            visitedTabs.insert(uiState.selectedTabIndex)
            uiState.showTabBar = true
            Task {
                await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded()
            }
        }
        .onChange(of: uiState.selectedTabIndex) { _, _ in
            normalizeSelectedTab()
            visitedTabs.insert(uiState.selectedTabIndex)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await PushRegistrationService.shared.uploadPendingTokenIfPossible()
                await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded()
            }
        }
    }

    // Keep visited screens and their data alive; initialize each screen only when opened.
    @ViewBuilder
    private func tabContent(_ index: Int) -> some View {
        switch index {
        case Tab.home.rawValue:
            SalespersonHomeView()
        case Tab.inbox.rawValue:
            SalespersonCommunicationsView()
        case Tab.contacts.rawValue:
            SalespersonLeadsView(mode: .contacts)
        case Tab.dialler.rawValue:
            SalespersonDiallerView()
        case Tab.followUp.rawValue:
            SalespersonFollowUpHubView()
        default:
            SalespersonHomeView()
        }
    }

    private func normalizeSelectedTab() {
        guard (Tab.home.rawValue...Tab.followUp.rawValue).contains(uiState.selectedTabIndex) else {
            uiState.selectedTabIndex = Tab.home.rawValue
            return
        }
    }
}
