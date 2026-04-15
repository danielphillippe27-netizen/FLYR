import SwiftUI
import CoreLocation
import Combine

/// Campaign Road Settings View
/// Shows road preparation status and allows manual re-preparation (needed if initial prep failed).
struct CampaignRoadSettingsView: View {
    let campaignId: String
    let campaignPolygon: [CLLocationCoordinate2D]?
    
    @StateObject private var viewModel = CampaignRoadSettingsViewModel()
    @State private var showRefreshConfirmation = false
    
    var body: some View {
        Section(header: Text("Campaign Roads")) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let subtitle = statusSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if viewModel.canRefresh, let polygon = campaignPolygon, !polygon.isEmpty {
                    Button {
                        showRefreshConfirmation = true
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(viewModel.status == .failed || viewModel.status == .pending ? "Prepare" : "Refresh")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .disabled(viewModel.isRefreshing)
                    .confirmationDialog(
                        "Refresh Campaign Roads?",
                        isPresented: $showRefreshConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Refresh Roads") {
                            viewModel.refreshRoads(campaignId: campaignId, polygon: polygon)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will re-fetch road data from Mapbox for this campaign. Existing road data will be replaced.")
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadMetadata(campaignId: campaignId)
        }
        .onChange(of: campaignId) { _, newId in
            viewModel.loadMetadata(campaignId: newId)
        }
    }
    
    private var statusIcon: String {
        switch viewModel.status {
        case .ready where !viewModel.isStale:
            return "checkmark.circle.fill"
        case .ready:
            return "exclamationmark.triangle.fill"
        case .pending, .fetching:
            return "clock.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch viewModel.status {
        case .ready where !viewModel.isStale:
            return .green
        case .ready:
            return .orange
        case .pending, .fetching:
            return .blue
        case .failed:
            return .red
        }
    }
    
    private var statusTitle: String {
        switch viewModel.status {
        case .ready where !viewModel.isStale:
            return "Roads Ready"
        case .ready:
            return "Roads Ready (Stale)"
        case .pending:
            return "Roads Pending"
        case .fetching:
            return "Fetching Roads..."
        case .failed:
            return "Roads Failed"
        }
    }
    
    private var statusSubtitle: String? {
        if viewModel.isRefreshing {
            return "Fetching roads from Mapbox..."
        }
        if viewModel.roadCount > 0 {
            let base = "\(viewModel.roadCount) roads"
            if let age = viewModel.ageDays {
                return "\(base) · \(Int(age))d old"
            }
            return base
        }
        if let error = viewModel.lastError {
            return error
        }
        if viewModel.status == .pending || viewModel.status == .failed {
            return "Tap Prepare to fetch roads for this campaign"
        }
        return nil
    }
}

// MARK: - View Model

@MainActor
class CampaignRoadSettingsViewModel: ObservableObject {
    @Published var status: CampaignRoadStatus = .pending
    @Published var roadCount: Int = 0
    @Published var ageDays: Double?
    @Published var isStale: Bool = false
    @Published var lastError: String?
    @Published var isRefreshing: Bool = false
    
    var canRefresh: Bool {
        !isRefreshing && status != .fetching
    }
    
    func loadMetadata(campaignId: String) {
        Task {
            do {
                let metadata = try await CampaignRoadService.shared.fetchCampaignRoadMetadata(campaignId: campaignId)
                self.status = metadata.status
                self.roadCount = metadata.roadCount
                self.ageDays = metadata.ageDays
                self.isStale = metadata.isStale
                self.lastError = metadata.lastErrorMessage
            } catch {
                print("❌ [CampaignRoadSettings] Failed to load metadata: \(error)")
            }
        }
    }
    
    func refreshRoads(campaignId: String, polygon: [CLLocationCoordinate2D]) {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let bounds = BoundingBox(from: polygon)
                let corridors = try await CampaignRoadService.shared.refreshCampaignRoads(
                    campaignId: campaignId,
                    bounds: bounds,
                    polygon: polygon
                )
                // Invalidate local device cache so next session picks up the fresh data
                await CampaignRoadDeviceCache.shared.clear(campaignId: campaignId)
                print("✅ [CampaignRoadSettings] Refreshed \(corridors.count) roads")
                loadMetadata(campaignId: campaignId)
            } catch {
                print("❌ [CampaignRoadSettings] Refresh failed: \(error)")
                loadMetadata(campaignId: campaignId)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    Form {
        CampaignRoadSettingsView(
            campaignId: UUID().uuidString,
            campaignPolygon: nil
        )
    }
}
