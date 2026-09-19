import SwiftUI

struct SalespersonCommunicationsView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @EnvironmentObject private var uiState: AppUIState
    @State private var isShowingConversation = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                filterBar
                Divider()
            }
            .frame(height: isShowingConversation ? 0 : nil)
            .opacity(isShowingConversation ? 0 : 1)
            .clipped()
            .allowsHitTesting(!isShowingConversation)

            selectedContent
                .id("\(auth.user?.id.uuidString ?? "signed-out"):\(workspace.workspaceId?.uuidString ?? "no-workspace")")
        }
        .background(Color(uiColor: .systemBackground))
        .onChange(of: isShowingConversation) { _, isShowing in
            withAnimation(.easeOut(duration: 0.2)) {
                uiState.showTabBar = !isShowing
            }
        }
        .onDisappear {
            uiState.showTabBar = true
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.flyrPrimary.opacity(0.16))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(profileInitials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.flyrPrimary)
                }

            Spacer()

            Text("My Inbox")
                .font(.system(size: 22, weight: .semibold))

            Spacer()

            Button {
                uiState.salespersonCommunicationFilter = .inbox
            } label: {
                Image(systemName: "bell.badge")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Show notifications and unread replies")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(SalespersonCommunicationFilter.allCases) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        uiState.salespersonCommunicationFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(uiState.salespersonCommunicationFilter == filter ? Color.primary : Color.secondary)
                        .background(
                            uiState.salespersonCommunicationFilter == filter
                                ? Color(uiColor: .systemBackground)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(uiState.salespersonCommunicationFilter == filter ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch uiState.salespersonCommunicationFilter {
        case .inbox:
            SalespersonInboxView(
                source: "all",
                title: "Inbox",
                isShowingThread: $isShowingConversation
            )
        case .messages:
            SalespersonInboxView(
                source: "sms",
                title: "Messages",
                isShowingThread: $isShowingConversation
            )
        case .email:
            SalespersonInboxView(
                source: "email",
                title: "Email",
                isShowingThread: $isShowingConversation
            )
        case .phone:
            SalespersonInboxView(
                source: "call",
                title: "Phone",
                isShowingThread: $isShowingConversation
            )
        }
    }

    private var profileInitials: String {
        let name = AuthManager.shared.user?.displayName ?? AuthManager.shared.user?.email ?? "WG"
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 2 {
            return String(parts.prefix(2).compactMap(\.first)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
