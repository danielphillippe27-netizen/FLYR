import SwiftUI
import Supabase
import Auth

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()
    @StateObject private var auth = AuthManager.shared
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                if let userID = auth.user?.id {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            headerSection
                            
                            // Streaks
                            streaksSection
                            
                            // Time Period Toggle
                            timePeriodToggle
                            
                            // Stats Grid
                            statsGridSection
                            
                            // Success Metrics
                            successMetricsSection
                            
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .refreshable {
                        await vm.refreshStats(for: userID)
                    }
                    .task {
                        await vm.loadStats(for: userID)
                    }
                } else {
                    // No user signed in
                    VStack(spacing: 16) {
                        Text("Please sign in to view your stats")
                            .font(.body)
                            .foregroundColor(.muted)
                    }
                }
            }
            .navigationTitle("Your Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.text)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Stats")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.text)
                
                Text("Updated just now")
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
            }
            
            Spacer()
            
            // Profile picture placeholder
            Circle()
                .fill(Color.bgSecondary)
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.info)
                        .font(.system(size: 24))
                )
        }
    }
    
    // MARK: - Streaks Section
    
    private var streaksSection: some View {
        HStack(spacing: 16) {
            StatCard(
                icon: "flame.fill",
                color: .orange,
                title: "Day Streak",
                value: vm.stats?.day_streak ?? 0
            )
            
            StatCard(
                icon: "trophy.fill",
                color: .yellow,
                title: "Best Streak",
                value: vm.stats?.best_streak ?? 0
            )
        }
    }
    
    // MARK: - Time Period Toggle
    
    private var timePeriodToggle: some View {
        Picker("Time Period", selection: $vm.selectedTab) {
            Text("Week").tag("Week")
            Text("All Time").tag("All Time")
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Stats Grid Section
    
    private var statsGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(
                icon: "door.left.hand.open",
                color: .blue,
                title: "Doors Knocked",
                value: vm.stats?.doors_knocked ?? 0
            )
            
            StatCard(
                icon: "doc.text",
                color: .green,
                title: "Flyers",
                value: vm.stats?.flyers ?? 0
            )
            
            StatCard(
                icon: "bubble.left.and.bubble.right.fill",
                color: .purple,
                title: "Conversations",
                value: vm.stats?.conversations ?? 0
            )
            
            StatCard(
                icon: "star.fill",
                color: .orange,
                title: "Leads Created",
                value: vm.stats?.leads_created ?? 0
            )
            
            StatCard(
                icon: "qrcode",
                color: .red,
                title: "QR Codes Scanned",
                value: vm.stats?.qr_codes_scanned ?? 0
            )
            
            StatCard(
                icon: "figure.walk",
                color: .cyan,
                title: "Distance Walked",
                value: vm.stats?.distance_walked ?? 0.0
            )
            
            StatCard(
                icon: "star.circle.fill",
                color: .yellow,
                title: "Experience Points",
                value: vm.stats?.xp ?? 0
            )
        }
    }
    
    // MARK: - Success Metrics Section
    
    private var successMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.green)
                    .font(.system(size: 18, weight: .medium))
                
                Text("Success Metrics")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.text)
            }
            
            VStack(spacing: 20) {
                SuccessMetricBar(
                    title: "Conversations per Door",
                    value: vm.stats?.conversation_per_door ?? 0.0,
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .purple,
                    description: "Conversations per door knocked"
                )
                
                SuccessMetricBar(
                    title: "Conversation-Lead Rate",
                    value: vm.stats?.conversation_lead_rate ?? 0.0,
                    icon: "star.fill",
                    color: .yellow,
                    description: "Leads per conversation"
                )
                
                SuccessMetricBar(
                    title: "FLYR™ QR Code Scan",
                    value: vm.stats?.qr_code_scan_rate ?? 0.0,
                    icon: "qrcode.viewfinder",
                    color: .red,
                    description: "QR code scans per flyer"
                )
                
                SuccessMetricBar(
                    title: "FLYR™ QR Code - Lead",
                    value: vm.stats?.qr_code_lead_rate ?? 0.0,
                    icon: "qrcode",
                    color: .orange,
                    description: "Leads per QR code scan"
                )
            }
            .padding(.top, 8)
        }
    }
}

