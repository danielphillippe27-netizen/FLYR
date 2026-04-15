import SwiftUI
import CoreLocation
import MapboxMaps

struct FarmDetailView: View {
    @EnvironmentObject private var uiState: AppUIState
    @StateObject private var viewModel: FarmDetailViewModel
    @State private var showAnalytics = false
    @State private var showFarmMap = false
    @State private var showTouchPlanner = false
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
        _viewModel = StateObject(wrappedValue: FarmDetailViewModel(farmId: farmId))
    }

    private var primaryCampaignIdForMap: UUID? {
        let addressCounts = Dictionary(grouping: viewModel.addresses, by: \.campaignId)
            .mapValues(\.count)

        if let mostCommonAddressCampaignId = addressCounts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.uuidString.localizedStandardCompare(rhs.key.uuidString) == .orderedAscending
            }
            return lhs.value < rhs.value
        })?.key {
            return mostCommonAddressCampaignId
        }

        let touchCampaignIds = viewModel.touches.compactMap(\.campaignId)
        let touchCounts = Dictionary(grouping: touchCampaignIds, by: { $0 })
            .mapValues(\.count)
        return touchCounts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.uuidString.localizedStandardCompare(rhs.key.uuidString) == .orderedAscending
            }
            return lhs.value < rhs.value
        })?.key
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let farm = viewModel.farm {
                    // Farm Summary Card
                    FarmSummaryCard(farm: farm)
                        .padding(.horizontal, 16)
                    
                    // Upcoming Touches
                    if !viewModel.upcomingTouches.isEmpty {
                        SectionHeader(title: "Upcoming Touches", icon: "calendar")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.upcomingTouches.prefix(5)) { touch in
                            TouchRowView(touch: touch)
                                .padding(.horizontal, 16)
                        }
                    }

                    PlanActionCard(
                        plannedCount: viewModel.touches.count,
                        completedCount: viewModel.touches.filter(\.completed).count,
                        cycleCount: viewModel.cycles.count,
                        onOpenPlanner: {
                            showTouchPlanner = true
                        }
                    )
                    .padding(.horizontal, 16)
                    
                    // Map Preview
                    if let polygon = farm.polygonCoordinates {
                        SectionHeader(title: "Farm Map", icon: "map")
                            .padding(.horizontal, 16)

                        Button {
                            if let campaignId = primaryCampaignIdForMap {
                                uiState.selectCampaign(id: campaignId, name: farm.name)
                                uiState.selectedTabIndex = 1
                            } else {
                                showFarmMap = true
                            }
                        } label: {
                            FarmMapPreview(
                                polygon: polygon,
                                addresses: viewModel.addresses
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        FarmAddressesCard(
                            addresses: viewModel.addresses,
                            fallbackCount: farm.addressCount
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    // Cycles
                    if !viewModel.cycles.isEmpty {
                        SectionHeader(title: "Cycles", icon: "repeat")
                            .padding(.horizontal, 16)

                        ForEach(viewModel.cycles) { cycle in
                            CycleCard(cycle: cycle)
                                .padding(.horizontal, 16)
                        }
                    } else {
                        Button {
                            Task {
                                await viewModel.generateCycles()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Generate Cycles")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Leads
                    if !viewModel.leads.isEmpty {
                        SectionHeader(title: "Leads", icon: "person.2")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.leads.prefix(5)) { lead in
                            LeadRowView(lead: lead)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // Recommendations
                    if !viewModel.recommendations.isEmpty {
                        SectionHeader(title: "Recommendations", icon: "lightbulb")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.recommendations) { rec in
                            RecommendationCard(recommendation: rec)
                                .padding(.horizontal, 16)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.farm?.name ?? "Farm")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAnalytics = true
                } label: {
                    Image(systemName: "chart.bar")
                }
            }
        }
        .sheet(isPresented: $showAnalytics) {
            if let farm = viewModel.farm {
                FarmAnalyticsView(farmId: farm.id)
            }
        }
        .sheet(isPresented: $showFarmMap) {
            if let farm = viewModel.farm {
                NavigationStack {
                    if let campaignId = primaryCampaignIdForMap {
                        CampaignMapView(
                            campaignId: campaignId.uuidString,
                            onDismissFromMap: {
                                showFarmMap = false
                            }
                        )
                    } else {
                        FarmMapView(
                            farm: farm,
                            addresses: viewModel.addresses
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showTouchPlanner, onDismiss: {
            Task {
                await viewModel.refreshAnalytics()
            }
        }) {
            NavigationStack {
                FarmTouchPlannerView(
                    farmId: farmId,
                    onStartSession: { context in
                        showTouchPlanner = false
                        uiState.beginPlannedFarmExecution(context)
                        uiState.selectedTabIndex = 1
                    }
                )
            }
        }
        .task {
            await viewModel.loadFarmData()
        }
        .refreshable {
            await viewModel.loadFarmData()
        }
    }
}

struct PlanActionCard: View {
    let plannedCount: Int
    let completedCount: Int
    let cycleCount: Int
    let onOpenPlanner: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan")
                .font(.flyrHeadline)

            HStack(spacing: 12) {
                PlanMetricPill(title: "Touches", value: "\(plannedCount)")
                PlanMetricPill(title: "Done", value: "\(completedCount)")
                PlanMetricPill(title: "Cycles", value: "\(cycleCount)")
            }

            Button(action: onOpenPlanner) {
                HStack {
                    Text("Open Planner")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.flyrSubheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct PlanMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.flyrHeadline)
            Text(title)
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
        )
    }
}

// MARK: - Farm Summary Card

struct FarmSummaryCard: View {
    let farm: Farm
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(farm.name)
                    .font(.flyrTitle2Bold)
                
                Spacer()
                
                Badge(text: farm.isActive ? "Active" : "Completed")
            }
            
            Text("\(farm.startDate, formatter: dateFormatter) - \(farm.endDate, formatter: dateFormatter)")
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Label("\(farm.frequency) touches/month", systemImage: "calendar")
                Spacer()
                Label("\(Int(farm.progress * 100))% complete", systemImage: "chart.pie")
            }
            .font(.flyrSubheadline)
            .foregroundStyle(.secondary)
            
            ProgressView(value: farm.progress)
                .tint(.red)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(title)
                .font(.flyrHeadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Touch Row View

struct TouchRowView: View {
    let touch: FarmTouch
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: touch.type.iconName)
                .foregroundColor(colorForTouchType(touch.type))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(touch.title)
                    .font(.flyrSubheadline)
                
                Text(touch.date, formatter: dateFormatter)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if touch.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private func colorForTouchType(_ type: FarmTouchType) -> Color {
        switch type {
        case .flyer: return .blue
        case .doorKnock: return .green
        case .event: return .flyrPrimary
        case .newsletter: return .purple
        case .ad: return .yellow
        case .custom: return .gray
        }
    }
}

// MARK: - Phase Card

struct CycleCard: View {
    let cycle: FarmCycle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cycle.cycleName)
                .font(.flyrHeadline)

            Text("\(cycle.startDate, style: .date) - \(cycle.endDate, style: .date)")
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Lead Row View

struct LeadRowView: View {
    let lead: FarmLead
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.name ?? "Unknown")
                    .font(.flyrSubheadline)
                
                Text(lead.leadSource.displayName)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: FarmRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(recommendation.title)
                    .font(.flyrHeadline)
            }
            
            Text(recommendation.detail)
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.yellow.opacity(0.1))
        )
    }
}

// MARK: - Farm Addresses Card

struct FarmAddressesCard: View {
    let addresses: [CampaignAddressViewRow]
    let fallbackCount: Int?

    private var displayedCount: Int? {
        if !addresses.isEmpty {
            return addresses.count
        }
        return fallbackCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(addresses.isEmpty ? "Buildings / addresses" : "Buildings / addresses loaded")
                } icon: {
                    Image(systemName: "house")
                }
                .font(.flyrSubheadline)
                .foregroundStyle(.primary)

                Spacer()

                if let count = displayedCount, count > 0 {
                    Text("\(count) homes")
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if !addresses.isEmpty {
                ForEach(addresses.prefix(4), id: \.id) { address in
                    Text(address.formatted)
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Homes inside this farm will appear here when address data is available.")
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Farm Map Preview

struct FarmMapPreview: View {
    let polygon: [CLLocationCoordinate2D]
    let addresses: [CampaignAddressViewRow]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FarmMapPreviewRepresentable(
            polygon: polygon,
            addresses: addresses,
            useDarkStyle: colorScheme == .dark
        )
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            Text(addresses.isEmpty ? "Farm boundary" : "\(addresses.count) homes")
                .font(.flyrCaption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            Label("Open map", systemImage: "arrow.up.right")
                .font(.flyrCaption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
    }
}

private struct FarmMapPreviewRepresentable: UIViewRepresentable {
    let polygon: [CLLocationCoordinate2D]
    let addresses: [CampaignAddressViewRow]
    let useDarkStyle: Bool

    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/streets-v11")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.rotateEnabled = false
        mapView.mapboxMap.loadStyle(useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI)

        let polygonManager = mapView.annotations.makePolygonAnnotationManager()
        let circleManager = mapView.annotations.makeCircleAnnotationManager()
        circleManager.circleRadius = 4
        circleManager.circleColor = StyleColor(.systemRed)
        circleManager.circleStrokeColor = StyleColor(.white)
        circleManager.circleStrokeWidth = 1.5

        context.coordinator.mapView = mapView
        context.coordinator.polygonAnnotationManager = polygonManager
        context.coordinator.addressAnnotationManager = circleManager
        context.coordinator.loadedStyleRawValue = (useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI).rawValue
        context.coordinator.boundStyleLoadedObserver(to: mapView)
        context.coordinator.sync(polygon: polygon, addresses: addresses)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        let fallbackSize = CGSize(width: 320, height: 240)
        let parentSize = mapView.superview?.bounds.size ?? .zero
        let resolvedSize: CGSize
        if parentSize.width.isFinite, parentSize.height.isFinite, parentSize.width > 0, parentSize.height > 0 {
            resolvedSize = parentSize
        } else {
            resolvedSize = fallbackSize
        }
        if mapView.bounds.size != resolvedSize {
            mapView.bounds = CGRect(origin: .zero, size: resolvedSize)
        }
        let scale = mapView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0, mapView.contentScaleFactor != scale {
            mapView.contentScaleFactor = scale
        }
        context.coordinator.sync(polygon: polygon, addresses: addresses)
        let desiredStyle = (useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI).rawValue
        if context.coordinator.loadedStyleRawValue != desiredStyle {
            context.coordinator.loadedStyleRawValue = desiredStyle
            mapView.mapboxMap.loadStyle(useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI)
        }
        mapView.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var mapView: MapView?
        var polygonAnnotationManager: PolygonAnnotationManager?
        var addressAnnotationManager: CircleAnnotationManager?
        var styleLoadedObserver: AnyCancelable?
        var loadedStyleRawValue: String?
        private var lastSignature: String?
        private var pendingPolygon: [CLLocationCoordinate2D] = []
        private var pendingAddresses: [CampaignAddressViewRow] = []

        func boundStyleLoadedObserver(to mapView: MapView) {
            guard styleLoadedObserver == nil else { return }
            styleLoadedObserver = mapView.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
                guard let self else { return }
                self.renderCurrentState()
            }
        }

        func sync(polygon: [CLLocationCoordinate2D], addresses: [CampaignAddressViewRow]) {
            pendingPolygon = polygon
            pendingAddresses = addresses
            renderCurrentState()
        }

        private func renderCurrentState() {
            guard let mapView else { return }

            var ring = pendingPolygon.map {
                LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            if ring.first != ring.last, let first = ring.first {
                ring.append(first)
            }
            if ring.count >= 4 {
                let polygon = Polygon([ring])
                let annotation = PolygonAnnotation(polygon: polygon)
                polygonAnnotationManager?.fillColor = StyleColor(UIColor.systemRed.withAlphaComponent(0.15))
                polygonAnnotationManager?.fillOutlineColor = StyleColor(.systemRed)
                polygonAnnotationManager?.annotations = [annotation]
            } else {
                polygonAnnotationManager?.annotations = []
            }

            let addressAnnotations = pendingAddresses.map { address in
                CircleAnnotation(
                    centerCoordinate: LocationCoordinate2D(
                        latitude: address.geom.coordinate.latitude,
                        longitude: address.geom.coordinate.longitude
                    )
                )
            }
            addressAnnotationManager?.annotations = addressAnnotations

            let signature = pendingPolygon
                .map { "\($0.latitude),\($0.longitude)" }
                .joined(separator: "|")
                + "::"
                + pendingAddresses.prefix(10).map { $0.id.uuidString }.joined(separator: "|")
            guard signature != lastSignature else { return }
            lastSignature = signature

            let allCoords = pendingPolygon + pendingAddresses.map(\.geom.coordinate)
            guard !allCoords.isEmpty else { return }
            fitCamera(on: mapView, coordinates: allCoords)
        }

        private func fitCamera(on mapView: MapView, coordinates: [CLLocationCoordinate2D]) {
            let lats = coordinates.map(\.latitude)
            let lons = coordinates.map(\.longitude)
            guard let minLat = lats.min(),
                  let maxLat = lats.max(),
                  let minLon = lons.min(),
                  let maxLon = lons.max() else { return }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let span = max(maxLat - minLat, maxLon - minLon)
            let zoom: CGFloat
            switch span {
            case ..<0.002: zoom = 16
            case ..<0.005: zoom = 15
            case ..<0.01: zoom = 14
            case ..<0.02: zoom = 13
            case ..<0.05: zoom = 12
            default: zoom = 11
            }

            mapView.camera.ease(
                to: CameraOptions(
                    center: center,
                    padding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
                    zoom: zoom,
                    bearing: 0,
                    pitch: 0
                ),
                duration: 0.5
            )
        }
    }
}

#Preview {
    NavigationStack {
        FarmDetailView(farmId: UUID())
    }
}
