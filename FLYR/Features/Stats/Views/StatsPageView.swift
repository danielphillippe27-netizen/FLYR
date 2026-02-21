import SwiftUI
import Supabase
enum StatsPageTab: String, CaseIterable {
    case leaderboard = "Leaderboard"
    case you = "You"
    
    var icon: String {
        switch self {
        case .leaderboard: return "trophy.fill"
        case .you: return "person.fill"
        }
    }
}

private let statsAccentRed = Color(hex: "#FF4F4F")

struct StatsPageView: View {
    @EnvironmentObject var entitlementsService: EntitlementsService
    @State private var selectedTab: StatsPageTab = .leaderboard
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            // Mode Picker (Leaderboard | You)
            ModeSegmentedPicker(selectedTab: $selectedTab)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .onChange(of: selectedTab) { _, _ in HapticManager.light() }

            // Content with smooth transition
            Group {
                switch selectedTab {
                case .leaderboard:
                    if entitlementsService.canUsePro {
                        LeaderboardView()
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        LeaderboardPaywallGate(showPaywall: $showPaywall)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                case .you:
                    YouViewContent()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Leaderboard Pro gate (upgrade CTA when not Pro)
private struct LeaderboardPaywallGate: View {
    @Binding var showPaywall: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Image(systemName: "trophy.fill")
                .font(.system(size: 56))
                .foregroundColor(.muted)
            Text("Leaderboard is a Pro feature")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.text)
                .multilineTextAlignment(.center)
            Text("Upgrade to see how you rank.")
                .font(.system(size: 16))
                .foregroundColor(.muted)
            Button {
                showPaywall = true
            } label: {
                Text("Upgrade to Pro")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#FF4F4F"))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Time filter pills (Week | All Time) below main toggle

struct TimeFilterPills: View {
    @Binding var period: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(["Week", "All Time"], id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        period = option
                    }
                } label: {
                    Text(option)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(period == option ? .white : .text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(period == option ? statsAccentRed : Color.gray.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: period)
            }
        }
    }
}

// MARK: - Progress bar max values (for bar width only; real value always shown)

private enum StatsProgressMax {
    static let doors = 200.0
    static let flyers = 200.0
    static let conversations = 100.0
    static let leads = 100.0
    static let appointments = 50.0
    static let distance = 20.0
    static let qrScans = 50.0
}

// MARK: - You View Content (All Time only)

struct YouViewContent: View {
    @StateObject private var vm = StatsViewModel()
    @StateObject private var auth = AuthManager.shared

    private let barAccent = Color(hex: "#FF4F4F")

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if let userID = auth.user?.id {
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero: streak section (slightly smaller)
                        streakRingSection
                            .frame(height: 115)
                            .padding(.top, 16)

                        // 4 percentage blocks
                        fourPercentRow
                            .frame(height: 64)
                            .padding(.top, 16)

                        // Metric rows
                        VStack(spacing: 14) {
                            CompactStatRow(
                                icon: "door.left.hand.open",
                                label: "Doors",
                                progress: progress(actual: Double(vm.stats?.doors_knocked ?? 0), max: StatsProgressMax.doors),
                                value: "\(vm.stats?.doors_knocked ?? 0)"
                            )
                            CompactStatRow(
                                icon: "bubble.left.and.bubble.right.fill",
                                label: "Convos",
                                progress: progress(actual: Double(vm.stats?.conversations ?? 0), max: StatsProgressMax.conversations),
                                value: "\(vm.stats?.conversations ?? 0)"
                            )
                            CompactStatRow(
                                icon: "person.badge.plus",
                                label: "Leads",
                                progress: progress(actual: Double(vm.stats?.leads_created ?? 0), max: StatsProgressMax.leads),
                                value: "\(vm.stats?.leads_created ?? 0)"
                            )
                            CompactStatRow(
                                icon: "calendar",
                                label: "Appointments",
                                progress: progress(actual: Double(vm.stats?.appointments ?? 0), max: StatsProgressMax.appointments),
                                value: "\(vm.stats?.appointments ?? 0)"
                            )
                            CompactStatRow(
                                icon: "figure.walk",
                                label: "Distance",
                                progress: progress(actual: vm.stats?.distance_walked ?? 0, max: StatsProgressMax.distance),
                                value: String(format: "%.1f mi", vm.stats?.distance_walked ?? 0)
                            )
                            CompactStatRow(
                                icon: "doc.text",
                                label: "Flyers",
                                progress: progress(actual: Double(vm.stats?.flyers ?? 0), max: StatsProgressMax.flyers),
                                value: "\(vm.stats?.flyers ?? 0)"
                            )
                            CompactStatRow(
                                icon: "qrcode",
                                label: "QR Scans",
                                progress: progress(actual: Double(vm.stats?.qr_codes_scanned ?? 0), max: StatsProgressMax.qrScans),
                                value: "\(vm.stats?.qr_codes_scanned ?? 0)"
                            )
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.automatic)
                .refreshable {
                    await vm.refreshStats(for: userID)
                    HapticManager.rigid()
                }
                .task {
                    await vm.loadStats(for: userID)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Please sign in to view your stats")
                        .font(.body)
                        .foregroundColor(.muted)
                }
            }
        }
    }

    private func progress(actual: Double, max: Double) -> Double {
        guard max > 0 else { return 0 }
        return min(1.0, actual / max)
    }

    private func safePercent(numerator: Double, denominator: Double) -> Double {
        guard denominator > 0 else { return 0 }
        return (numerator / denominator) * 100
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    // MARK: - Streak hero (compact)

    private var streakRingSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundColor(barAccent)
                Text("\(vm.stats?.day_streak ?? 0)")
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.text)
            }
            Text("days")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4 percentage blocks

    private var fourPercentRow: some View {
        let doors = Double(vm.stats?.doors_knocked ?? 0)
        let conv = Double(vm.stats?.conversations ?? 0)
        let leads = Double(vm.stats?.leads_created ?? 0)
        let appts = Double(vm.stats?.appointments ?? 0)
        let flyers = Double(vm.stats?.flyers ?? 0)
        let qr = Double(vm.stats?.qr_codes_scanned ?? 0)
        return HStack(spacing: 0) {
            miniColumn(label: "D→C %", value: formatPercent(safePercent(numerator: conv, denominator: doors)))
            miniColumn(label: "C→L %", value: formatPercent(safePercent(numerator: leads, denominator: conv)))
            miniColumn(label: "C→A %", value: formatPercent(safePercent(numerator: appts, denominator: conv)))
            miniColumn(label: "F→Q %", value: formatPercent(safePercent(numerator: qr, denominator: flyers)))
        }
        .padding(.horizontal, 8)
    }

    private func miniColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.muted)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.text)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - You Stats View (push from Home grid; All Time only)
struct YouStatsView: View {
    var body: some View {
        YouViewContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Leaderboard Tab View (tab 4 only; no toggle)
struct LeaderboardTabView: View {
    @EnvironmentObject var entitlementsService: EntitlementsService
    @State private var showPaywall = false

    var body: some View {
        Group {
            if entitlementsService.canUsePro {
                LeaderboardView()
            } else {
                LeaderboardPaywallGate(showPaywall: $showPaywall)
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

#Preview {
    NavigationStack {
        StatsPageView()
    }
}

