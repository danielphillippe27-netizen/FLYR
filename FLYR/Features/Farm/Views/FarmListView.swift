import SwiftUI
import Supabase

struct FarmListView: View {
    @StateObject private var viewModel = FarmViewModel()
    @State private var farmFilter: FarmFilter = .active
    @State private var recentlyCreatedFarmID: UUID?
    @State private var searchText = ""
    @EnvironmentObject var authManager: AuthManager
    var externalFilter: Binding<FarmFilter>? = nil
    var onCreateFarmTapped: (() -> Void)?

    private var effectiveFilter: FarmFilter {
        externalFilter?.wrappedValue ?? farmFilter
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if externalFilter == nil {
                    HStack {
                        Menu {
                            ForEach(FarmFilter.allCases) { filterOption in
                                Button(filterOption.rawValue) {
                                    HapticManager.light()
                                    farmFilter = filterOption
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(farmFilter.rawValue)
                                Image(systemName: "chevron.down")
                                    .font(.flyrCaption)
                            }
                            .font(.flyrSubheadline)
                            .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                }

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
                        .padding(.top, 60)
                    } else {
                        FarmListEmptyView(onCreateTapped: onCreateFarmTapped)
                    }
                } else {
                    List {
                        FarmListSection(
                            viewModel: viewModel,
                            filter: effectiveFilter,
                            searchText: searchText,
                            recentlyCreatedFarmID: recentlyCreatedFarmID
                        )
                        FarmListEmptyFilteredSection(
                            viewModel: viewModel,
                            filter: effectiveFilter,
                            searchText: searchText
                        )
                        if let onCreateFarmTapped = onCreateFarmTapped {
                            Section {
                                Button(action: {
                                    HapticManager.light()
                                    onCreateFarmTapped()
                                }) {
                                    HStack {
                                        Spacer()
                                        Text("+ New Farm")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundColor(.red)
                                        Spacer()
                                    }
                                    .padding(.vertical, 14)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.bgSecondary)
                    .searchable(text: $searchText, prompt: "Search farms")
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: effectiveFilter)
            .onChange(of: viewModel.farms.count) { oldCount, newCount in
                if newCount > oldCount, let newFarm = viewModel.farms.last {
                    recentlyCreatedFarmID = newFarm.id
                }
            }
            .onChange(of: recentlyCreatedFarmID) { oldID, newID in
                if let newID = newID {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                HapticManager.rigid()
            }
        }
    }
}

// MARK: - Farm Filter

enum FarmFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case completed = "Completed"
    case all = "All"

    var id: String { rawValue }
}

// MARK: - Farm List Section

struct FarmListSection: View {
    let viewModel: FarmViewModel
    let filter: FarmFilter
    var searchText: String = ""
    let recentlyCreatedFarmID: UUID?

    private var filteredFarms: [Farm] {
        switch filter {
        case .active:
            return viewModel.farms.filter { $0.isActive }
        case .completed:
            return viewModel.farms.filter { $0.isCompleted }
        case .all:
            return viewModel.farms
        }
    }

    private var sortedFarms: [Farm] {
        filteredFarms.sorted { a, b in
            let aActive = a.isActive
            let bActive = b.isActive
            if aActive != bActive { return aActive }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var searchFilteredFarms: [Farm] {
        guard !searchText.isEmpty else { return sortedFarms }
        let q = searchText.lowercased()
        return sortedFarms.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.areaLabel?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    var body: some View {
        if !viewModel.farms.isEmpty && !searchFilteredFarms.isEmpty {
            Section {
                ForEach(Array(searchFilteredFarms.enumerated()), id: \.element.id) { index, farm in
                    NavigationLink(destination: FarmDetailView(farmId: farm.id)) {
                        FarmRowView(farm: farm)
                            .background(
                                farm.id == recentlyCreatedFarmID
                                    ? Color.red.opacity(0.15)
                                    : Color.clear
                            )
                            .animation(.easeInOut(duration: 0.3), value: recentlyCreatedFarmID)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let userId = AuthManager.shared.user?.id {
                                Task { await viewModel.deleteFarm(farm, userId: userId) }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            // Edit: tap row to open detail
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Color(.systemGray))
                    }
                    .contextMenu {
                        Button {
                            // Tap row to open detail for edit
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            // TODO: Duplicate farm when API exists
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        Button {
                            // TODO: Archive when store supports
                        } label: {
                            Label("Archive", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            if let userId = AuthManager.shared.user?.id {
                                Task { await viewModel.deleteFarm(farm, userId: userId) }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .staggeredAnimation(delay: Double(index) * Animation.staggerDelay)
                    .id(farm.id)
                }
            }
        }
    }
}

// MARK: - Empty filtered section (when filter or search yields no farms)

struct FarmListEmptyFilteredSection: View {
    let viewModel: FarmViewModel
    let filter: FarmFilter
    var searchText: String = ""

    private var filteredFarms: [Farm] {
        switch filter {
        case .active: return viewModel.farms.filter { $0.isActive }
        case .completed: return viewModel.farms.filter { $0.isCompleted }
        case .all: return viewModel.farms
        }
    }

    private var afterSearchCount: Int {
        guard !searchText.isEmpty else { return filteredFarms.count }
        let q = searchText.lowercased()
        return filteredFarms.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.areaLabel?.localizedCaseInsensitiveContains(q) == true)
        }.count
    }

    var body: some View {
        if !viewModel.farms.isEmpty && afterSearchCount == 0 {
            Section {
                Text(searchText.isEmpty
                    ? "No \(filter.rawValue.lowercased()) farms"
                    : "No results for \"\(searchText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 40)
            }
        }
    }
}

// MARK: - Farm List Empty View (no farms at all)

struct FarmListEmptyView: View {
    var onCreateTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "leaf.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.secondary)
                .opacity(0.6)
            VStack(spacing: 12) {
                Text("No farms yet")
                    .font(.flyrHeadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text("Create your first farm to start planning touches")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if let onCreateTapped = onCreateTapped {
                Button(action: onCreateTapped) {
                    Text("+ Create Farm")
                }
                .primaryButton()
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        FarmListView()
            .environmentObject(AuthManager.shared)
    }
}
