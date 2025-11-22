import SwiftUI
import Supabase
import Combine

/// View to list and manage landing pages grouped by campaign
struct LandingPagesView: View {
    @StateObject private var viewModel = LandingPagesViewModel()
    @State private var showCreateView = false
    @State private var selectedLandingPageId: UUID?
    
    var body: some View {
        ZStack {
            Color.bgSecondary.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.landingPagesByCampaign.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.landingPagesByCampaign.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { campaignId in
                            if let campaignName = viewModel.campaignNames[campaignId],
                               let landingPages = viewModel.landingPagesByCampaign[campaignId] {
                                landingPagesSection(campaignName: campaignName, landingPages: landingPages)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateView = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.accentDefault)
                }
            }
        }
        .sheet(isPresented: $showCreateView) {
            NavigationStack {
                QRWorkflowLandingPageCreateWrapper(onSave: { landingPageId in
                    selectedLandingPageId = landingPageId
                    Task {
                        await viewModel.loadLandingPages()
                    }
                })
            }
        }
        .task {
            await viewModel.loadLandingPages()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundColor(.muted)
            
            Text("No Landing Pages")
                .font(.headline)
                .foregroundColor(.text)
            
            Text("Create your first landing page to get started")
                .font(.subheadline)
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
            
            Button {
                showCreateView = true
            } label: {
                Text("Create Landing Page")
                    .primaryButton()
            }
            .padding(.top, 8)
        }
        .padding()
    }
    
    private func landingPagesSection(campaignName: String, landingPages: [CampaignLandingPage]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(campaignName)
                .font(.headline)
                .foregroundColor(.text)
                .padding(.horizontal, 4)
            
            ForEach(landingPages) { landingPage in
                NavigationLink {
                    CreateQRView(selectedLandingPageId: landingPage.id, selectedCampaignId: landingPage.campaignId)
                } label: {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            if let headline = landingPage.headline, !headline.isEmpty {
                                Text(headline)
                                    .font(.headline)
                                    .foregroundColor(.text)
                            }
                            
                            if let subheadline = landingPage.subheadline, !subheadline.isEmpty {
                                Text(subheadline)
                                    .font(.subheadline)
                                    .foregroundColor(.muted)
                            }
                            
                            HStack {
                                Text("Slug: \(landingPage.slug)")
                                    .font(.caption)
                                    .foregroundColor(.muted)
                                
                                Spacer()
                                
                                if let ctaType = landingPage.ctaType {
                                    Text(ctaType.rawValue.uppercased())
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentDefault.opacity(0.1))
                                        .foregroundColor(.accentDefault)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

@MainActor
class LandingPagesViewModel: ObservableObject {
    @Published var landingPages: [CampaignLandingPage] = []
    @Published var landingPagesByCampaign: [UUID: [CampaignLandingPage]] = [:]
    @Published var campaignNames: [UUID: String] = [:]
    @Published var isLoading = false
    @Published var error: String?
    
    private let landingPageService = SupabaseLandingPageService.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    func loadLandingPages() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Fetch all landing pages
            let response: PostgrestResponse<[CampaignLandingPage]> = try await SupabaseManager.shared.client
                .from("campaign_landing_pages")
                .select()
                .order("created_at", ascending: false)
                .execute()
            
            landingPages = response.value
            
            // Group by campaign
            var grouped: [UUID: [CampaignLandingPage]] = [:]
            for landingPage in response.value {
                if grouped[landingPage.campaignId] == nil {
                    grouped[landingPage.campaignId] = []
                }
                grouped[landingPage.campaignId]?.append(landingPage)
            }
            landingPagesByCampaign = grouped
            
            // Fetch campaign names
            let campaignIds = Set(landingPages.map { $0.campaignId })
            for campaignId in campaignIds {
                do {
                    let campaign = try await campaignsAPI.fetchCampaign(id: campaignId)
                    campaignNames[campaignId] = campaign.title
                } catch {
                    campaignNames[campaignId] = "Unknown Campaign"
                }
            }
        } catch {
            self.error = "Failed to load landing pages: \(error.localizedDescription)"
            print("❌ [LandingPagesViewModel] Error: \(error)")
        }
    }
}

