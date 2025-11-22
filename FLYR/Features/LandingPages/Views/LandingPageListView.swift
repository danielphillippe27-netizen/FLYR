import SwiftUI
import Combine

/// List view for landing pages in a campaign
public struct LandingPageListView: View {
    let campaignId: UUID
    @StateObject private var viewModel = LandingPageListViewModel()
    
    public init(campaignId: UUID) {
        self.campaignId = campaignId
    }
    
    public var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
            } else if let pages = viewModel.pages {
                ForEach(pages) { page in
                    NavigationLink(destination: LandingPageEditorView(pageData: page.toLandingPageData())) {
                        LandingPageRow(page: page)
                    }
                }
            }
        }
        .navigationTitle("Landing Pages")
        .task {
            await viewModel.loadPages(campaignId: campaignId)
        }
    }
}

/// View model for landing page list
@MainActor
final class LandingPageListViewModel: ObservableObject {
    @Published var pages: [LandingPage]?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let landingPagesAPI = LandingPagesAPI.shared
    
    func loadPages(campaignId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            pages = try await landingPagesAPI.fetchLandingPagesForCampaign(campaignId: campaignId)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading landing pages: \(error)")
        }
    }
}

/// Landing page row
struct LandingPageRow: View {
    let page: LandingPage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(page.title ?? page.name)
                .font(.headline)
            if let subtitle = page.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let slug = page.slug {
                Text(slug)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
}

