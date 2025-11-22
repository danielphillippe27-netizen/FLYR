import SwiftUI
import Combine

/// Analytics view for landing pages
public struct LandingPageAnalyticsView: View {
    let campaignId: UUID
    @StateObject private var viewModel = LandingPageAnalyticsViewModel()
    
    public init(campaignId: UUID) {
        self.campaignId = campaignId
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                } else if let analytics = viewModel.analytics {
                    // Summary Cards
                    summaryCards(analytics: analytics)
                    
                    // Per-Address Performance
                    perAddressPerformance(analytics: analytics)
                    
                    // Top Streets
                    topStreets(analytics: analytics)
                } else if let error = viewModel.errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Landing Page Analytics")
        .task {
            await viewModel.loadAnalytics(campaignId: campaignId)
        }
    }
    
    // MARK: - Summary Cards
    
    private func summaryCards(analytics: CampaignLandingPageAnalyticsLegacy) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            LandingPageStatCard(title: "Total Scans", value: "\(analytics.totalScans)")
            LandingPageStatCard(title: "Total Views", value: "\(analytics.totalViews)")
            LandingPageStatCard(title: "Total Clicks", value: "\(analytics.totalClicks)")
            LandingPageStatCard(title: "CTR", value: String(format: "%.1f%%", analytics.overallCTR * 100))
        }
    }
    
    // MARK: - Per-Address Performance
    
    private func perAddressPerformance(analytics: CampaignLandingPageAnalyticsLegacy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Address Performance")
                .font(.headline)
            
            ForEach(analytics.perAddressPerformance.prefix(10)) { performance in
                AddressPerformanceRow(performance: performance)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Top Streets
    
    private func topStreets(analytics: CampaignLandingPageAnalyticsLegacy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Streets")
                .font(.headline)
            
            ForEach(analytics.topStreets, id: \.street) { street in
                HStack {
                    Text(street.street)
                        .font(.subheadline)
                    Spacer()
                    Text("\(street.views) views")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

/// View model for analytics
@MainActor
final class LandingPageAnalyticsViewModel: ObservableObject {
    @Published var analytics: CampaignLandingPageAnalyticsLegacy?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let analyticsService = LandingPageAnalyticsService.shared
    
    func loadAnalytics(campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            analytics = try await analyticsService.getCampaignAnalytics(campaignId: campaignId)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading analytics: \(error)")
        }
    }
}

/// Landing page stat card component
struct LandingPageStatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

/// Address performance row
struct AddressPerformanceRow: View {
    let performance: AddressPerformance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(performance.addressFormatted)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Label("\(performance.views)", systemImage: "eye")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Label("\(performance.clicks)", systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(performance.formattedCTR)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .divider()
    }
}

extension View {
    func divider() -> some View {
        self.overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

