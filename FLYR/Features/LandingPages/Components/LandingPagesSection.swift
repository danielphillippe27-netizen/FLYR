import SwiftUI
import Combine

/// Landing Pages section for campaign detail view
struct LandingPagesSection: View {
    let campaignId: UUID
    let campaign: CampaignV2
    @StateObject private var viewModel = LandingPagesSectionViewModel()
    @State private var showEditor = false
    @State private var showList = false
    @State private var showAnalytics = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Landing Pages")
                    .font(.subheading)
                    .foregroundColor(.text)
                
                Spacer()
                
                if viewModel.isGenerating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Generate All Button
            Button(action: {
                Task {
                    await viewModel.generateAllPages(campaignId: campaignId)
                }
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Generate Landing Pages for \(campaign.addresses.count) addresses")
                }
                .font(.label)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accent)
                .cornerRadius(8)
            }
            .disabled(viewModel.isGenerating)
            
            // Quick Actions
            HStack(spacing: 12) {
                Button(action: {
                    showList = true
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("View All")
                    }
                    .font(.caption)
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.bgTertiary)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    showAnalytics = true
                }) {
                    HStack {
                        Image(systemName: "chart.bar")
                        Text("Analytics")
                    }
                    .font(.caption)
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.bgTertiary)
                    .cornerRadius(8)
                }
            }
            
            // Status
            if let status = viewModel.status {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.muted)
            }
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
        .sheet(isPresented: $showList) {
            NavigationStack {
                LandingPageListView(campaignId: campaignId)
            }
        }
        .sheet(isPresented: $showAnalytics) {
            NavigationStack {
                LandingPageAnalyticsView(campaignId: campaignId)
            }
        }
    }
}

/// View model for landing pages section
@MainActor
final class LandingPagesSectionViewModel: ObservableObject {
    @Published var isGenerating = false
    @Published var status: String?
    
    private let bulkGenerator = BulkLandingPageGenerator.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    func generateAllPages(campaignId: UUID) async {
        isGenerating = true
        status = "Starting generation..."
        defer { isGenerating = false }
        
        do {
            // Fetch campaign
            let campaignDB = try await campaignsAPI.fetchCampaignDBRow(id: campaignId)
            
            // Generate pages with progress
            let pages = try await bulkGenerator.generateForAllAddresses(
                campaign: campaignDB
            ) { progress in
                await MainActor.run {
                    self.status = "Generated \(Int(progress * 100))%..."
                }
            }
            
            status = "Generated \(pages.count) landing pages"
        } catch {
            status = "Error: \(error.localizedDescription)"
            print("❌ Error generating landing pages: \(error)")
        }
    }
}

