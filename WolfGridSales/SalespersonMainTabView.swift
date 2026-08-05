import SwiftUI

/// The root experience for the private WolfGrid Sales app.
///
/// This intentionally has no dependency on the field-app campaign/session
/// navigation. The Sales target always presents these seven salesperson tools.
struct SalespersonMainTabView: View {
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.scenePhase) private var scenePhase

    private enum Tab: Int {
        case home = 0
        case phone = 1
        case messages = 2
        case emails = 3
        case contacts = 4
        case list = 5
        case followUp = 6
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch uiState.selectedTabIndex {
                case Tab.home.rawValue:
                    SalespersonHomeView()
                case Tab.phone.rawValue:
                    SalespersonDiallerView()
                case Tab.messages.rawValue:
                    SalespersonInboxView(source: "sms", title: "Messages")
                case Tab.emails.rawValue:
                    SalespersonInboxView(source: "email", title: "Emails")
                case Tab.contacts.rawValue:
                    SalespersonLeadsView(mode: .contacts)
                case Tab.list.rawValue:
                    SalespersonLeadsView(mode: .lists)
                case Tab.followUp.rawValue:
                    SalespersonTasksView()
                default:
                    SalespersonHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if uiState.showTabBar {
                UberStyleTabBar(
                    selectedIndex: uiState.selectedTabIndex,
                    onSelect: { index in
                        HapticManager.tabSwitch()
                        uiState.selectedTabIndex = index
                    },
                    onCreate: {},
                    recordHighlight: false,
                    accentColor: .red,
                    mode: .salesperson
                )
            }
        }
        .background(Color.bg)
        .onAppear {
            normalizeSelectedTab()
            uiState.showTabBar = true
            Task {
                await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded()
            }
        }
        .onChange(of: uiState.selectedTabIndex) { _, _ in
            normalizeSelectedTab()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await PushRegistrationService.shared.uploadPendingTokenIfPossible()
                await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded()
            }
        }
    }

    private func normalizeSelectedTab() {
        guard (Tab.home.rawValue...Tab.followUp.rawValue).contains(uiState.selectedTabIndex) else {
            uiState.selectedTabIndex = Tab.home.rawValue
            return
        }
    }
}
