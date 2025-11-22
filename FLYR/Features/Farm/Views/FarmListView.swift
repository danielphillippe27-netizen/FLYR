import SwiftUI
import Supabase

struct FarmListView: View {
    @StateObject private var viewModel = FarmViewModel()
    @State private var filter: FarmFilter = .active
    @State private var recentlyCreatedFarmID: UUID?
    
    @EnvironmentObject var authManager: AuthManager
    
    var filteredFarms: [Farm] {
        switch filter {
        case .active:
            return viewModel.farms.filter { $0.isActive }
        case .completed:
            return viewModel.farms.filter { $0.isCompleted }
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Segmented control - full width
                    Picker("Filter", selection: $filter) {
                        ForEach(FarmFilter.allCases) { filterOption in
                            Text(filterOption.rawValue).tag(filterOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    FarmSection(
                        farms: filteredFarms,
                        recentlyCreatedFarmID: recentlyCreatedFarmID
                    )
                    
                    FarmEmptyStateSection(
                        viewModel: viewModel,
                        filter: filter
                    )
                }
                .padding(.horizontal, 16)
            }
            .background(Color.bgSecondary)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: filter)
            .onChange(of: viewModel.farms.count) { oldCount, newCount in
                // Detect new farm added
                if newCount > oldCount, let newFarm = viewModel.farms.last {
                    recentlyCreatedFarmID = newFarm.id
                }
            }
            .onChange(of: recentlyCreatedFarmID) { oldID, newID in
                if let newID = newID {
                    // Scroll to the newly created farm
                    withAnimation(.easeInOut(duration: 0.6)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    
                    // Clear highlight after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await MainActor.run {
                            recentlyCreatedFarmID = nil
                        }
                    }
                }
            }
            .navigationDestination(for: Farm.self) { farm in
                FarmDetailView(farmId: farm.id)
            }
            .task {
                if let userId = authManager.user?.id {
                    await viewModel.loadFarms(userId: userId)
                }
            }
            .refreshable {
                if let userId = authManager.user?.id {
                    await viewModel.refresh(userId: userId)
                }
            }
        }
    }
}

// MARK: - Farm Filter

enum FarmFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case completed = "Completed"
    
    var id: String { rawValue }
}

// MARK: - Farm Section

struct FarmSection: View {
    let farms: [Farm]
    let recentlyCreatedFarmID: UUID?
    
    var body: some View {
        if !farms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(farms.enumerated()), id: \.element.id) { index, farm in
                    NavigationLink(destination: FarmDetailView(farmId: farm.id)) {
                        FarmRowView(farm: farm)
                            .background(
                                farm.id == recentlyCreatedFarmID ?
                                    Color.red.opacity(0.15) : Color.clear
                            )
                            .animation(.easeInOut(duration: 0.3), value: recentlyCreatedFarmID)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .staggeredAnimation(delay: Double(index) * Animation.staggerDelay)
                    .id(farm.id) // Required for ScrollViewReader
                }
            }
        }
    }
}

// MARK: - Empty State Section

struct FarmEmptyStateSection: View {
    let viewModel: FarmViewModel
    let filter: FarmFilter
    
    var body: some View {
        if viewModel.farms.isEmpty {
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading farms...")
                        .bodyText()
                        .foregroundColor(.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                EmptyState.simple(
                    illustration: "leaf.circle",
                    title: "No Farms Yet"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            }
        } else if !viewModel.farms.isEmpty {
            let filtered = filter == .active 
                ? viewModel.farms.filter { $0.isActive }
                : viewModel.farms.filter { $0.isCompleted }
            if filtered.isEmpty {
                // Show empty state when there are farms but none match the filter
                VStack(spacing: 8) {
                    Text("No \(filter.rawValue.lowercased()) farms")
                        .font(.body)
                        .foregroundColor(.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FarmListView()
            .environmentObject(AuthManager.shared)
    }
}
