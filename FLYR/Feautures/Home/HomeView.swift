import SwiftUI

private enum HomeRoute: Hashable {
    case campaigns
    case quickStart
    case activity
    case stats
    case support
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [HomeRoute] = []
    @State private var showingNewCampaign = false
    @StateObject private var storeV2 = CampaignV2Store.shared
    @StateObject private var auth = AuthManager.shared
    @StateObject private var reportsViewModel = IndividualPerformanceReportViewModel()
    @State private var dailyContent = DailyContentService.shared
    @State private var selectedCampaignID: UUID?
    @State private var showingPerformanceReports = false

    /// PNG from asset catalog: white logo for dark mode, black logo for light mode.
    private var headerLogoName: String {
        colorScheme == .dark ? "white Logo" : "Black Logo"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                homeGrid
                    .blur(radius: showingPerformanceReports ? 8 : 0)
                    .disabled(showingPerformanceReports)

                if showingPerformanceReports {
                    performanceReportsOverlay
                        .zIndex(50)
                }
            }
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
                        path.append(.support)
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewCampaign = true
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
            .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .campaigns:
                        CampaignsView()
                    case .quickStart:
                        QuickStartMapView()
                    case .activity:
                        ActivityView()
                    case .stats:
                        YouStatsView()
                    case .support:
                        SupportChatView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
        }
        .task(id: auth.user?.id) {
            guard let userID = auth.user?.id else { return }
            await reportsViewModel.refreshUnreadIndicator(for: userID)
        }
        .onChange(of: showingPerformanceReports) { _, isPresented in
            guard !isPresented, let userID = auth.user?.id else { return }
            Task { await reportsViewModel.refreshUnreadIndicator(for: userID) }
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
    }

    private var homeGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Quote of the Day (no card, bigger text)
                QuoteOfTheDaySection(
                    quote: dailyContent.quote,
                    isLoading: dailyContent.isLoading
                )
                .padding(.top, 44)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                // 2x2 grid + Weekly Report (same width, flush; full width minus horizontal padding)
                VStack(spacing: 0) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        HomeGridTile(title: "Campaigns", icon: "scope") {
                            path.append(.campaigns)
                        }
                        HomeGridTile(title: "Quick Start", icon: "bolt.fill") {
                            // Guard against rapid double-taps pushing duplicate quick-start screens.
                            if path.last != .quickStart {
                                path.append(.quickStart)
                            }
                        }
                        HomeGridTile(title: "Activity", icon: "figure.walk") {
                            path.append(.activity)
                        }
                        HomeGridTile(title: "Stats", icon: "chart.bar.fill") {
                            path.append(.stats)
                        }
                    }
                    .padding(.top, 4)

                    WeeklyReportButton(hasUnread: reportsViewModel.hasUnread) {
                        openPerformanceReports()
                    }
                        .padding(.top, 16)
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

    private var performanceReportsOverlay: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingPerformanceReports = false
                    }
                }

            IndividualPerformanceReportModal(
                reports: reportsViewModel.reports,
                isLoading: reportsViewModel.isLoading,
                errorMessage: reportsViewModel.errorMessage,
                onRefresh: {
                    guard let userID = auth.user?.id else { return }
                    Task {
                        await reportsViewModel.loadReports(
                            userID: userID,
                            workspaceID: WorkspaceContext.shared.workspaceId
                        )
                    }
                },
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingPerformanceReports = false
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func openPerformanceReports() {
        guard let userID = auth.user?.id else { return }

        HapticManager.light()
        withAnimation(.easeInOut(duration: 0.2)) {
            showingPerformanceReports = true
        }

        Task {
            await reportsViewModel.openAndMarkRead(
                userID: userID,
                workspaceID: WorkspaceContext.shared.workspaceId
            )
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
    let icon: String
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
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(foreground)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 120)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Individual Performance Reports CTA
private struct WeeklyReportButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let hasUnread: Bool
    let action: () -> Void

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text("Performance Reports")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.15), lineWidth: 1)
                    )

                if hasUnread {
                    Circle()
                        .fill(Color.flyrPrimary)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.85), lineWidth: 1)
                        )
                        .offset(x: -10, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppUIState())
}
