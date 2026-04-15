import SwiftUI

private enum HomeRoute: Hashable {
    case campaigns
    case farm
    case activity
    case stats
    case routes
    case challenges
    case support
}

private enum PendingAfterPaywall {
    case none
    case farm
}

private enum HomeGridTileIcon {
    case system(String)
    case farmGlyph
    case routesGlyph
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @State private var selectedRoute: HomeRoute?
    @State private var showingNewCampaign = false
    @State private var showPaywall = false
    @StateObject private var storeV2 = CampaignV2Store.shared
    @StateObject private var auth = AuthManager.shared
    @State private var dailyContent = DailyContentService.shared

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
                            createCampaignTapped()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(width: 36, height: 36)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationDestination(item: $selectedRoute) { route in
                    switch route {
                    case .campaigns:
                        CampaignsView()
                    case .farm:
                        FarmsView()
                    case .activity:
                        ActivityView()
                    case .stats:
                        YouStatsView()
                    case .routes:
                        RoutesListView()
                    case .challenges:
                        ChallengesHomeView()
                    case .support:
                        SupportChatView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
        }
        .onAppear {
            selectedRoute = nil
        }
        .fullScreenCover(isPresented: $showingNewCampaign) {
            NavigationStack {
                NewCampaignScreen(store: storeV2)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showingNewCampaign = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            switch pendingAfterPaywall {
            case .farm:
                if entitlementsService.canUsePro, selectedRoute != .farm {
                    selectedRoute = .farm
                }
            case .none:
                break
            }
            pendingAfterPaywall = .none
        }) {
            PaywallView()
                .environmentObject(entitlementsService)
        }
    }

    @State private var pendingAfterPaywall: PendingAfterPaywall = .none

    private var homeGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                QuoteOfTheDaySection(
                    quote: dailyContent.quote,
                    isLoading: dailyContent.isLoading
                )
                .padding(.top, 44)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        HomeGridTile(title: "Campaigns", icon: .system("scope")) {
                            selectedRoute = .campaigns
                        }
                        HomeGridTile(title: "Farm", icon: .farmGlyph) {
                            farmTapped()
                        }
                        HomeGridTile(title: "Activity", icon: .system("figure.walk")) {
                            selectedRoute = .activity
                        }
                        HomeGridTile(title: "Stats", icon: .system("chart.bar.fill")) {
                            selectedRoute = .stats
                        }
                        HomeGridTile(title: "Routes", icon: .routesGlyph) {
                            selectedRoute = .routes
                        }
                        HomeGridTile(title: "Challenges", icon: .system("flag.fill")) {
                            selectedRoute = .challenges
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

    private func farmTapped() {
        if entitlementsService.canUsePro {
            if selectedRoute != .farm {
                selectedRoute = .farm
            }
            return
        }
        pendingAfterPaywall = .farm
        showPaywall = true
    }

    private func createCampaignTapped() {
        HapticManager.light()
        showingNewCampaign = true
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
                    case .farmGlyph:
                        Image(systemName: "leaf")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(foreground)
                            .frame(width: 34, height: 28)
                    case .routesGlyph:
                        RoutesGlyph(color: foreground, lineWidth: 2.8)
                            .frame(width: 34, height: 28)
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

/// Matches FLYR-PRO’s Lucide `Route` icon (lucide-react `route`: 24×24 viewBox).
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
