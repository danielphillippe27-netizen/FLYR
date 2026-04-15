import SwiftUI

struct CampaignsView: View {
    /// Flip to `true` to restore the toolbar chart button and confidence diagnostics sheet.
    private static let showConfidenceDiagnosticsToolbar = false

    @State private var campaignFilter: CampaignFilter = .active
    @State private var showingNewCampaign = false
    @State private var showingConfidenceDiagnostics = false
    @State private var selectedCampaignID: UUID?

    @StateObject private var storeV2 = CampaignV2Store.shared
    @EnvironmentObject private var uiState: AppUIState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                listContent
            }
            .navigationTitle("Campaigns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(CampaignFilter.allCases) { filterOption in
                                Button(filterOption.rawValue) {
                                    campaignFilter = filterOption
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(campaignFilter.rawValue)
                                    .font(.system(size: 15, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.primary)
                        }

                        if canViewConfidenceDiagnostics {
                            Button {
                                showingConfidenceDiagnostics = true
                            } label: {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 34, height: 34)
                                    .background(Color.bgSecondary)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open confidence diagnostics")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createCampaignTapped()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(item: $selectedCampaignID) { campaignID in
                NewCampaignDetailView(campaignID: campaignID, store: storeV2)
            }
        }
        .sheet(isPresented: $showingConfidenceDiagnostics) {
            NavigationStack {
                CampaignConfidenceDiagnosticsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingConfidenceDiagnostics = false
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showingNewCampaign) {
            NavigationStack {
                NewCampaignScreen(store: storeV2)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showingNewCampaign = false
                            }
                        }
                }
            }
        }
        .onAppear {
            storeV2.routeToV2Detail = { campaignID in
                selectedCampaignID = campaignID
            }
        }
    }

    private var canViewConfidenceDiagnostics: Bool {
        guard Self.showConfidenceDiagnosticsToolbar else { return false }
        guard let role = WorkspaceContext.shared.role?.lowercased() else { return false }
        return role == "owner" || role == "admin" || role == "team_lead" || role == "lead"
    }

    private var listContent: some View {
        CampaignsListView(
            externalFilter: $campaignFilter,
            showCreateCampaign: $showingNewCampaign,
            onCreateCampaignTapped: createCampaignTapped,
            onCampaignTapped: { selectedCampaignID = $0 }
        )
    }

    /// Same action for toolbar + and empty state "+ Create Campaign" button.
    private func createCampaignTapped() {
        HapticManager.light()
        showingNewCampaign = true
    }
}

#Preview {
    CampaignsView()
        .environmentObject(AppUIState())
}

private struct CampaignConfidenceDiagnosticsView: View {
    @StateObject private var workspaceContext = WorkspaceContext.shared
    @State private var hotspots: [CampaignConfidenceHotspot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPrecision: HotspotPrecision = .city
    @State private var sortOption: HotspotSortOption = .priority

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                controlsCard
                contentSection
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Confidence Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedPrecision) {
            await loadHotspots()
        }
        .refreshable {
            await loadHotspots(force: true)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prioritize the areas where campaign demand is strong but confidence is weak.")
                .font(.subheading)
                .foregroundColor(.text)

            Text(workspaceSummaryText)
                .font(.flyrFootnote)
                .foregroundColor(.muted)

            HStack(spacing: 12) {
                summaryTile(
                    title: "Campaigns",
                    value: "\(totalCampaignsRepresented)"
                )
                summaryTile(
                    title: "Avg Confidence",
                    value: "\(Int((weightedAverageConfidence * 100).rounded()))%"
                )
                summaryTile(
                    title: "Weak Cells",
                    value: "\(weakCellCount)"
                )
            }

            if let topHotspot = sortedHotspots.first, !hotspots.isEmpty {
                HStack(spacing: 8) {
                    Text("Top opportunity")
                        .font(.flyrCaption.weight(.semibold))
                        .foregroundColor(.muted)
                    Text(topHotspot.geohash.uppercased())
                        .font(.flyrCaption.weight(.semibold))
                        .foregroundColor(.text)
                    Text("•")
                        .foregroundColor(.muted)
                    Text("\(topHotspot.campaignsCount) campaigns")
                        .font(.flyrCaption)
                        .foregroundColor(.muted)
                }
            }
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grouping")
                .font(.label)
                .foregroundColor(.text)

            SegmentedControl(
                options: HotspotPrecision.allCases.map { option in
                    SegmentedOption(option.title, value: option)
                },
                selection: $selectedPrecision
            )

            HStack {
                Text("Sort")
                    .font(.label)
                    .foregroundColor(.text)

                Spacer()

                Menu {
                    ForEach(HotspotSortOption.allCases) { option in
                        Button(option.title) {
                            sortOption = option
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(sortOption.title)
                            .font(.flyrFootnote.weight(.semibold))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .foregroundColor(.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.bgTertiary)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var contentSection: some View {
        if isLoading && hotspots.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading confidence hotspots…")
                    .font(.flyrFootnote)
                    .foregroundColor(.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn’t load diagnostics")
                    .font(.subheading)
                    .foregroundColor(.text)
                Text(errorMessage)
                    .font(.flyrFootnote)
                    .foregroundColor(.muted)
                Button("Try Again") {
                    Task {
                        await loadHotspots(force: true)
                    }
                }
                .font(.flyrFootnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.bgSecondary)
            .cornerRadius(12)
        } else if sortedHotspots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No hotspot data yet")
                    .font(.subheading)
                    .foregroundColor(.text)
                Text("Once campaigns are provisioned with confidence scores, this view will highlight the cells with the biggest quality gaps.")
                    .font(.flyrFootnote)
                    .foregroundColor(.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.bgSecondary)
            .cornerRadius(12)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(sortedHotspots.enumerated()), id: \.element.geohash) { index, hotspot in
                    hotspotCard(hotspot, rank: index + 1)
                }
            }
        }
    }

    private func hotspotCard(_ hotspot: CampaignConfidenceHotspot, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(rank) \(hotspot.geohash.uppercased())")
                        .font(.subheading)
                        .foregroundColor(.text)
                    Text("Priority \(hotspot.priorityScore.formatted(.number.precision(.fractionLength(1))))")
                        .font(.flyrFootnote)
                        .foregroundColor(.muted)
                }

                Spacer()

                Text(hotspotLabel(for: hotspot).title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(confidenceForegroundColor(for: hotspotLabel(for: hotspot)))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(confidenceBackgroundColor(for: hotspotLabel(for: hotspot)))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                hotspotMetricTile(title: "Campaigns", value: "\(hotspot.campaignsCount)")
                hotspotMetricTile(title: "Confidence", value: "\(Int((hotspot.avgConfidenceScore * 100).rounded()))%")
                hotspotMetricTile(title: "Linked", value: "\(Int((hotspot.avgLinkedCoverage * 100).rounded()))%")
            }

            HStack(spacing: 12) {
                hotspotMetricTile(title: "Low", value: "\(hotspot.lowCount)")
                hotspotMetricTile(title: "Medium", value: "\(hotspot.mediumCount)")
                hotspotMetricTile(title: "High", value: "\(hotspot.highCount)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Source mix")
                    .font(.flyrFootnote.weight(.semibold))
                    .foregroundColor(.text)

                HStack(spacing: 8) {
                    sourceChip(title: "Gold", value: hotspot.goldExactTotal, color: .green)
                    sourceChip(title: "Silver", value: hotspot.silverTotal, color: .orange)
                    sourceChip(title: "Lambda", value: hotspot.lambdaTotal, color: .blue)
                    sourceChip(title: "Bronze", value: hotspot.bronzeTotal, color: .brown)
                }
            }

            HStack {
                Text(String(format: "Lat %.4f • Lon %.4f", hotspot.centerLat, hotspot.centerLon))
                    .font(.flyrCaption)
                    .foregroundColor(.muted)

                Spacer()

                if let mapsURL = hotspot.appleMapsURL {
                    Link(destination: mapsURL) {
                        Text("Open Map")
                            .font(.flyrCaption.weight(.semibold))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.muted)
            Text(value)
                .font(.headline)
                .foregroundColor(.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bgTertiary)
        .cornerRadius(10)
    }

    private func hotspotMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.muted)
            Text(value)
                .font(.headline)
                .foregroundColor(.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bgTertiary)
        .cornerRadius(10)
    }

    private func sourceChip(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title) \(value)")
                .font(.flyrCaption.weight(.semibold))
                .foregroundColor(.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .cornerRadius(999)
    }

    private var sortedHotspots: [CampaignConfidenceHotspot] {
        switch sortOption {
        case .priority:
            return hotspots.sorted { lhs, rhs in
                if lhs.priorityScore != rhs.priorityScore {
                    return lhs.priorityScore > rhs.priorityScore
                }
                return lhs.campaignsCount > rhs.campaignsCount
            }
        case .volume:
            return hotspots.sorted { lhs, rhs in
                if lhs.campaignsCount != rhs.campaignsCount {
                    return lhs.campaignsCount > rhs.campaignsCount
                }
                return lhs.priorityScore > rhs.priorityScore
            }
        case .weakest:
            return hotspots.sorted { lhs, rhs in
                if lhs.avgConfidenceScore != rhs.avgConfidenceScore {
                    return lhs.avgConfidenceScore < rhs.avgConfidenceScore
                }
                return lhs.campaignsCount > rhs.campaignsCount
            }
        }
    }

    private var totalCampaignsRepresented: Int {
        hotspots.reduce(0) { $0 + $1.campaignsCount }
    }

    private var weightedAverageConfidence: Double {
        guard totalCampaignsRepresented > 0 else { return 0 }
        let weightedTotal = hotspots.reduce(0.0) { partial, hotspot in
            partial + (hotspot.avgConfidenceScore * Double(hotspot.campaignsCount))
        }
        return weightedTotal / Double(totalCampaignsRepresented)
    }

    private var weakCellCount: Int {
        hotspots.filter { hotspot in
            hotspot.avgConfidenceScore < 0.65 || hotspot.lowCount > 0
        }.count
    }

    private var workspaceSummaryText: String {
        let scope = workspaceContext.workspaceName ?? "your accessible workspaces"
        return "Grouped at the \(selectedPrecision.title.lowercased()) level for \(scope). Use this to spot where better Gold coverage or better linking would help most."
    }

    private func loadHotspots(force _: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            hotspots = try await CampaignsAPI.shared.fetchCampaignConfidenceHotspots(
                precision: selectedPrecision.value,
                workspaceId: workspaceContext.workspaceId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hotspotLabel(for hotspot: CampaignConfidenceHotspot) -> DataConfidenceLabel {
        if hotspot.avgConfidenceScore >= 0.85 {
            return .high
        }
        if hotspot.avgConfidenceScore >= 0.65 {
            return .medium
        }
        return .low
    }

    private func confidenceForegroundColor(for label: DataConfidenceLabel) -> Color {
        switch label {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }

    private func confidenceBackgroundColor(for label: DataConfidenceLabel) -> Color {
        switch label {
        case .high:
            return Color.green.opacity(0.12)
        case .medium:
            return Color.orange.opacity(0.12)
        case .low:
            return Color.red.opacity(0.12)
        }
    }
}

private enum HotspotPrecision: Int, CaseIterable, Identifiable {
    case broad = 4
    case city = 5
    case neighborhood = 6

    var id: Int { rawValue }

    var value: Int { rawValue }

    var title: String {
        switch self {
        case .broad:
            return "Broad"
        case .city:
            return "City"
        case .neighborhood:
            return "Tight"
        }
    }
}

private enum HotspotSortOption: String, CaseIterable, Identifiable {
    case priority
    case volume
    case weakest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priority:
            return "Priority"
        case .volume:
            return "Volume"
        case .weakest:
            return "Weakest"
        }
    }
}

private extension CampaignConfidenceHotspot {
    var appleMapsURL: URL? {
        URL(string: "http://maps.apple.com/?ll=\(centerLat),\(centerLon)&q=\(geohash)")
    }
}
