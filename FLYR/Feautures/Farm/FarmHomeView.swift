import SwiftUI

struct FarmHomeView: View {
    @State private var farmFilter: FarmHomeFilter = .active
    @State private var showCreate = false
    
    // TODO: Replace with actual Farm store/hooks when implemented
    @State private var farms: [FarmPlaceholder] = []
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Segmented control - full width
                Picker("Filter", selection: $farmFilter) {
                    ForEach(FarmHomeFilter.allCases) { filterOption in
                        Text(filterOption.rawValue).tag(filterOption)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                if !farms.isEmpty {
                    FarmsSection(farms: farms, filter: farmFilter)
                } else {
                    FarmPlaceholderEmptyStateSection(isLoading: isLoading, filter: farmFilter)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color.bgSecondary)
        .navigationTitle("Farm")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showCreate) {
            FarmCreateView()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: farmFilter)
    }
}

// MARK: - Farm Filter

enum FarmHomeFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case completed = "Completed"
    
    var id: String { rawValue }
}

// MARK: - Farms Section

struct FarmsSection: View {
    let farms: [FarmPlaceholder]
    let filter: FarmHomeFilter
    
    var filteredFarms: [FarmPlaceholder] {
        switch filter {
        case .active:
            return farms.filter { !$0.isCompleted }
        case .completed:
            return farms.filter { $0.isCompleted }
        }
    }
    
    var body: some View {
        if !filteredFarms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(filteredFarms.enumerated()), id: \.element.id) { index, farm in
                    FarmHomeRowView(farm: farm)
                        .staggeredAnimation(delay: Double(index) * Animation.staggerDelay)
                }
            }
        }
    }
}

// MARK: - Empty State Section (Legacy)

struct FarmPlaceholderEmptyStateSection: View {
    let isLoading: Bool
    let filter: FarmHomeFilter
    
    var body: some View {
        if isLoading {
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
            VStack(spacing: 16) {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("No Farms Yet")
                    .font(.title3.weight(.semibold))
                Text("Create a farm plan to repeatedly work an area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 100)
        }
    }
}

// MARK: - Farm Row View

struct FarmHomeRowView: View {
    let farm: FarmPlaceholder
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
    
    private var progressPercentage: Int {
        Int(farm.progress * 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Name and Badge
            HStack {
                Text(farm.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                
                Spacer()
                
                Badge(text: "Farm")
            }
            
            // Created date
            Text("Created \(farm.createdAt, formatter: dateFormatter)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Progress section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(progressPercentage)%")
                        .font(.subheadline)
                        .foregroundColor(.text)
                }
                
                ProgressView(value: farm.progress)
                    .tint(.red)
            }
            
            // Stats row
            HStack {
                Label("\(farm.addressCount) addresses", systemImage: "paperplane")
                    .font(.subheadline)
                    .foregroundColor(.text)
                
                Spacer()
                
                if let areaLabel = farm.areaLabel {
                    Text(areaLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Every \(farm.frequencyDays) days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .shadow(
            color: Color.black.opacity(0.5),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}

// MARK: - Farm Placeholder (Temporary until real model is implemented)

struct FarmPlaceholder: Identifiable {
    let id: UUID
    let name: String
    let areaLabel: String?
    let addressCount: Int
    let frequencyDays: Int
    let isCompleted: Bool
    let createdAt: Date
    
    var progress: Double {
        // TODO: Calculate based on actual farm progress
        return 0.0
    }
}

#Preview {
    NavigationStack {
        FarmHomeView()
    }
}
