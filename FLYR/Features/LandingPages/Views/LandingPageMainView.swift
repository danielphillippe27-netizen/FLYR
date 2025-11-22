import SwiftUI

struct LandingPageMainView: View {
    @StateObject private var viewModel = LandingPageMainViewModel()
    @State private var showCreateView = false
    @State private var showEditView = false
    @State private var showQRCodesView = false
    @State private var showAnalyticsView = false
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Campaign Selector
                if viewModel.isLoadingCampaigns {
                    ProgressView()
                        .padding()
                } else {
                    CampaignSelector(
                        campaigns: viewModel.campaigns,
                        selectedId: viewModel.selectedCampaignId,
                        onSelect: { campaignId in
                            Task {
                                await viewModel.loadLandingPage(campaignId: campaignId)
                            }
                        }
                    )
                }
                
                Divider()
                
                // Landing Page Content
                if let campaignId = viewModel.selectedCampaignId {
                    if viewModel.isLoading {
                        ProgressView("Loading landing page...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let landingPage = viewModel.landingPage {
                        // Landing Page Exists
                        landingPageExistsView(landingPage: landingPage)
                    } else {
                        // No Landing Page
                        emptyStateView(campaignId: campaignId)
                    }
                } else {
                    EmptyState(
                        illustration: "globe",
                        title: "Select a Campaign",
                        message: "Choose a campaign to view or create its landing page"
                    )
                }
            }
        }
        .navigationTitle("Landing Page")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadCampaigns()
        }
        .navigationDestination(isPresented: $showCreateView) {
            if let campaignId = viewModel.selectedCampaignId,
               let campaign = viewModel.campaigns.first(where: { $0.id == campaignId }) {
                LandingPageCreateView(
                    campaignId: campaignId,
                    campaignName: campaign.name,
                    onCreated: {
                        Task {
                            await viewModel.loadLandingPage(campaignId: campaignId)
                        }
                    }
                )
            }
        }
        .navigationDestination(isPresented: $showEditView) {
            if let landingPage = viewModel.landingPage {
                LandingPageEditView(
                    landingPage: landingPage,
                    onUpdated: {
                        Task {
                            if let campaignId = viewModel.selectedCampaignId {
                                await viewModel.loadLandingPage(campaignId: campaignId)
                            }
                        }
                    }
                )
            }
        }
        .navigationDestination(isPresented: $showQRCodesView) {
            if let landingPage = viewModel.landingPage,
               let campaignId = viewModel.selectedCampaignId {
                LandingPageQRCodesView(
                    campaignId: campaignId,
                    landingPageId: landingPage.id
                )
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(campaignId: UUID) -> some View {
        EmptyState(
            illustration: "globe",
            title: "No Landing Page Yet",
            message: "Create a landing page for this campaign.",
            buttonTitle: "Create Landing Page",
            buttonAction: {
                showCreateView = true
            }
        )
    }
    
    // MARK: - Landing Page Exists View
    
    private func landingPageExistsView(landingPage: CampaignLandingPage) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preview Card
                landingPagePreviewCard(landingPage: landingPage)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // Action Buttons Grid
                actionButtonsGrid()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }
    
    private func landingPagePreviewCard(landingPage: CampaignLandingPage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hero Media (Image/Video/YouTube)
            if let heroUrl = landingPage.heroUrl, let url = URL(string: heroUrl) {
                switch landingPage.heroType {
                case .image:
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.bgSecondary)
                            .overlay {
                                ProgressView()
                            }
                    }
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(14)
                    
                case .video:
                    VStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accent)
                        Text("Video")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.muted)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.bgSecondary)
                    .cornerRadius(14)
                    
                case .youtube:
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accent)
                        Text("YouTube Video")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.muted)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.bgSecondary)
                    .cornerRadius(14)
                }
            }
            
            // Title
            if let title = landingPage.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.text)
            }
            
            // Headline
            if let headline = landingPage.headline, !headline.isEmpty {
                Text(headline)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.text)
            }
            
            // Subheadline
            if let subheadline = landingPage.subheadline, !subheadline.isEmpty {
                Text(subheadline)
                    .font(.system(size: 16))
                    .foregroundColor(.muted)
            }
        }
        .padding(20)
        .background(Color.bgSecondary)
        .cornerRadius(14)
    }
    
    private func actionButtonsGrid() -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            actionButton(
                title: "Edit Content",
                icon: "pencil",
                color: .blue
            ) {
                showEditView = true
            }
            
            actionButton(
                title: "Preview Live Page",
                icon: "safari",
                color: .green
            ) {
                if let url = URL(string: "https://flyr.app/l/\(viewModel.landingPage?.slug ?? "")") {
                    UIApplication.shared.open(url)
                }
            }
            
            actionButton(
                title: "Manage QR Codes",
                icon: "qrcode",
                color: .orange
            ) {
                showQRCodesView = true
            }
            
            actionButton(
                title: "View Analytics",
                icon: "chart.bar.fill",
                color: .purple
            ) {
                showAnalyticsView = true
            }
        }
    }
    
    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.bgSecondary)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}


