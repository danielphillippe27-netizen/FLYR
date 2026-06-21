import SwiftUI
import Combine
import PostgREST
import Storage
import Supabase

private enum HomeRoute: Hashable {
    case campaigns
    case campaign(UUID)
    case activity
    case appointments
    case followUp
    case stats
    case leaderboard
    case routes
    case support
}

private enum HomeGridTileIcon {
    case system(String)
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var uiState: AppUIState
    @State private var selectedRoute: HomeRoute?
    @StateObject private var auth = AuthManager.shared
    @StateObject private var profileImageLoader = HomeProfileImageLoader()
    @StateObject private var onboardingDemo = OnboardingDemoViewModel.shared
    @StateObject private var campaignStore = CampaignV2Store.shared
    @State private var dailyContent = DailyContentService.shared
    @State private var showingNewCampaign = false

    /// PNG from asset catalog: white logo for dark mode, black logo for light mode.
    private var headerLogoName: String {
        colorScheme == .dark ? "white Logo" : "Black Logo"
    }

    var body: some View {
        NavigationStack {
            homeGrid
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: 12)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            selectedRoute = .support
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                    ToolbarItem(placement: .principal) {
                        Image(headerLogoName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 360, maxHeight: 80)
                            .offset(y: 6)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticManager.light()
                            uiState.selectedTabIndex = 4
                        } label: {
                            profileToolbarIcon
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationDestination(item: $selectedRoute) { route in
                    switch route {
                    case .campaigns:
                        CampaignsView()
                    case .campaign(let campaignID):
                        NewCampaignDetailView(campaignID: campaignID, store: campaignStore)
                    case .activity:
                        ActivityView(
                            initialFilter: .activity,
                            filters: [.activity],
                            navigationTitle: "Activity"
                        )
                    case .appointments:
                        ActivityView(
                            initialFilter: .appointments,
                            filters: [.appointments],
                            navigationTitle: "Appointments"
                        )
                    case .followUp:
                        ActivityView(
                            initialFilter: .followUp,
                            filters: [.followUp],
                            navigationTitle: "Follow Up"
                        )
                    case .stats:
                        YouStatsView()
                    case .leaderboard:
                        LeaderboardTabView()
                    case .routes:
                        RoutesListView()
                    case .support:
                        SupportChatView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
        }
        .fullScreenCover(isPresented: $showingNewCampaign) {
            NavigationStack {
                NewCampaignScreen(store: campaignStore)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showingNewCampaign = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            selectedRoute = nil
        }
        .task(id: auth.user?.id) {
            await profileImageLoader.load(for: auth.user?.id)
            await onboardingDemo.load()
        }
    }

    @ViewBuilder
    private var profileToolbarIcon: some View {
        if let image = profileImageLoader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.12), lineWidth: 1)
                )
        } else if let user = auth.user {
            ProfileAvatarView(
                avatarUrl: user.photoURL?.absoluteString,
                name: user.displayName ?? user.email,
                size: 36
            )
            .overlay(
                Circle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.12), lineWidth: 1)
            )
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 36, height: 36)
        }
    }

    private var homeGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                QuoteOfTheDaySection(
                    quote: dailyContent.quote,
                    isLoading: dailyContent.isLoading
                )
                .padding(.top, 44)
                .padding(.horizontal, 24)
                .padding(.bottom, onboardingDemo.shouldShowPanel ? 16 : 28)

                if onboardingDemo.shouldShowPanel, let state = onboardingDemo.state {
                    OnboardingDemoPanel(
                        state: state,
                        items: onboardingDemo.checklistItems,
                        completedIDs: onboardingDemo.completedItemIDs,
                        isSeeding: onboardingDemo.isSeeding,
                        onDismiss: {
                            Task { await onboardingDemo.dismiss() }
                        },
                        onTapItem: handleDemoChecklistTap
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        HomeGridTile(title: "Campaign", icon: .system("scope")) {
                            selectedRoute = .campaigns
                        }
                        HomeGridTile(title: "Activity", icon: .system("figure.walk")) {
                            selectedRoute = .activity
                        }
                        HomeGridTile(title: "Follow Up", icon: .system("arrow.uturn.right.circle.fill")) {
                            selectedRoute = .followUp
                        }
                        HomeGridTile(title: "Appointments", icon: .system("calendar.badge.clock")) {
                            selectedRoute = .appointments
                        }
                        HomeGridTile(title: "Stats", icon: .system("chart.bar.fill")) {
                            selectedRoute = .stats
                        }
                        HomeGridTile(title: "Leaderboard", icon: .system("trophy.fill")) {
                            selectedRoute = .leaderboard
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .background(HomeGradientBackground())
        .task(id: "dailyContent") {
            await dailyContent.fetch()
        }
    }

    private func handleDemoChecklistTap(_ item: OnboardingDemoChecklistItem) {
        HapticManager.light()
        Task {
            await onboardingDemo.markComplete(item.id)
            await MainActor.run {
                route(for: item.action)
            }
        }
    }

    @MainActor
    private func route(for action: OnboardingDemoAction) {
        switch action {
        case .openStarterCampaign:
            if let campaignId = onboardingDemo.state?.seededCampaignId {
                selectedRoute = .campaign(campaignId)
            } else {
                selectedRoute = .campaigns
            }
        case .openCampaigns:
            selectedRoute = .campaigns
        case .openRecord:
            uiState.selectedTabIndex = 1
        case .openLeads:
            uiState.selectedTabIndex = 2
        case .openLeaderboard:
            selectedRoute = .leaderboard
        case .openRoutes:
            selectedRoute = .routes
        case .createStarterCampaign:
            Task {
                if let campaignId = await onboardingDemo.seedStarterCampaign() {
                    await onboardingDemo.markComplete(itemIdForCreateStarter)
                    await MainActor.run {
                        selectedRoute = .campaign(campaignId)
                    }
                }
            }
        case .createRealCampaign:
            showingNewCampaign = true
        case .none:
            break
        }
    }

    private var itemIdForCreateStarter: String {
        "create_starter_campaign"
    }
}

@MainActor
private final class HomeProfileImageLoader: ObservableObject {
    @Published var image: UIImage?

    private let supabase = SupabaseManager.shared.client

    func load(for userID: UUID?) async {
        image = nil
        guard let userID else { return }

        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value

            guard let path = profile.profileImageURL, !path.isEmpty else { return }

            let signedURL = try await supabase.storage
                .from("profile_images")
                .createSignedURL(path: path, expiresIn: 60 * 60 * 24 * 7)

            let (data, _) = try await URLSession.shared.data(from: signedURL)
            image = UIImage(data: data)
        } catch {
            image = nil
        }
    }
}

// MARK: - Gradient background (top band only, most of home is dark)
private struct HomeGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            stops: colorScheme == .dark
                ? [.init(color: .red, location: 0), .init(color: .red, location: 0.08), .init(color: .black, location: 0.35), .init(color: .black, location: 1)]
                : [.init(color: .red, location: 0), .init(color: .red, location: 0.08), .init(color: Color.white.opacity(0.95), location: 0.4), .init(color: .white, location: 1)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Quote of the Day (no card, bolder; white dark / black light)
private struct QuoteOfTheDaySection: View {
    @Environment(\.colorScheme) private var colorScheme
    let quote: DailyQuote?
    let isLoading: Bool

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Group {
            if isLoading && quote == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quote of the Day")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(textColor)
                    Text("Loading…")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(textColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let quote = quote {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quote of the Day")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(textColor)
                    Text(quote.text)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(quote.author)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct HomeGridTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: HomeGridTileIcon
    let action: () -> Void

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Button(action: {
            HapticManager.light()
            action()
        }) {
            VStack(spacing: 12) {
                Group {
                    switch icon {
                    case .system(let systemName):
                        Image(systemName: systemName)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(foreground)
                    }
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 120)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Matches FLYR-PRO's Lucide `Route` icon (lucide-react `route`: 24x24 viewBox).
struct RoutesGlyph: View {
    var color: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let s = min(w, h) / 24
            let ox = (w - 24 * s) / 2
            let oy = (h - 24 * s) / 2
            let toLocal: (CGFloat, CGFloat) -> CGPoint = { x, y in
                CGPoint(x: ox + x * s, y: oy + y * s)
            }
            let nodeR = 3 * s
            let arcR = 3.5 * s
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            ZStack {
                Path { path in
                    path.move(to: toLocal(9, 19))
                    path.addLine(to: toLocal(17.5, 19))
                    path.addArc(
                        center: toLocal(17.5, 15.5),
                        radius: arcR,
                        startAngle: .radians(.pi / 2),
                        endAngle: .radians(-.pi / 2),
                        clockwise: false
                    )
                    path.addLine(to: toLocal(6.5, 12))
                    path.addArc(
                        center: toLocal(6.5, 8.5),
                        radius: arcR,
                        startAngle: .radians(.pi / 2),
                        endAngle: .radians(-.pi / 2),
                        clockwise: true
                    )
                    path.addLine(to: toLocal(15, 5))
                }
                .stroke(color, style: stroke)

                Circle()
                    .strokeBorder(color, lineWidth: lineWidth)
                    .frame(width: nodeR * 2, height: nodeR * 2)
                    .position(toLocal(6, 19))

                Circle()
                    .strokeBorder(color, lineWidth: lineWidth)
                    .frame(width: nodeR * 2, height: nodeR * 2)
                    .position(toLocal(18, 5))
            }
        }
        .aspectRatio(1.2, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppUIState())
}
