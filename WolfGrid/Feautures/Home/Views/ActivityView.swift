import SwiftUI
import MapboxMaps
import CoreLocation

struct ActivityView: View {
    @StateObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var selectedFilter: ActivityFeedFilter
    @State private var items: [ActivityFeedItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSessionDetail: ActivitySessionDetailItem?
    @State private var selectedEditableItem: ActivityFeedItem?
    @State private var loadingSessionItemId: String?
    @State private var showSessionError = false
    private let filters: [ActivityFeedFilter]
    private let navigationTitle: String

    init(
        initialFilter: ActivityFeedFilter = .activity,
        filters: [ActivityFeedFilter] = ActivityFeedFilter.allCases,
        navigationTitle: String = "Activity"
    ) {
        let resolvedFilters = filters.isEmpty ? ActivityFeedFilter.allCases : filters
        self.filters = resolvedFilters
        self.navigationTitle = navigationTitle
        _selectedFilter = State(initialValue: resolvedFilters.contains(initialFilter) ? initialFilter : resolvedFilters[0])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if filters.count > 1 {
                filterTabs
            }
            Group {
                if isLoading {
                    loadingView
                } else if let message = errorMessage {
                    errorView(message: message)
                } else if items.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadItems()
        }
        .task {
            await loadItems()
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadItems() }
        }
        .alert("Couldn’t load session.", isPresented: $showSessionError) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $selectedSessionDetail) { item in
            NavigationStack {
                ActivitySessionDetailView(session: item.session)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $selectedEditableItem) { item in
            ActivityFeedEditSheet(item: item) { title, address, dueDate, notes in
                try await ActivityFeedService.shared.saveEditedItem(
                    item,
                    title: title,
                    address: address,
                    dueDate: dueDate,
                    notes: notes
                )
                await loadItems()
            }
            .presentationDetents([.height(430), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var filterTabs: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedFilter == filter ? .text : .muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selectedFilter == filter ? Color.white.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(selectedFilter.rawValue.lowercased())...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName(for: selectedFilter))
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(emptyMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    activityRow(item)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func activityRow(_ item: ActivityFeedItem) -> some View {
        let rowContent = activityRowContent(item)
        if item.kind == .session {
            return AnyView(
                Button {
                    openSessionDetail(for: item)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(loadingSessionItemId != nil)
            )
        } else {
            return AnyView(
                Button {
                    selectedEditableItem = item
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            )
        }
    }

    private func activityRowContent(_ item: ActivityFeedItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tintColor(for: item.kind).opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: symbolName(for: item.kind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tintColor(for: item.kind))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if loadingSessionItemId == item.id {
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.muted)
                    .frame(minWidth: 48, alignment: .trailing)
            } else {
                if item.kind == .session {
                    Text(trailingLabel(for: item))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.trailing)
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(item.timestamp, style: .relative)
                            .font(.system(size: 12, weight: .medium))
                        if let dueDate = item.dueDate {
                            Text(dueDateLabel(for: dueDate))
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary.opacity(0.75))
        )
    }

    private func trailingLabel(for item: ActivityFeedItem) -> String {
        let durationText = formatSessionDuration(item.sessionDurationSeconds)
        let dateText = sessionDateFormatter.string(from: item.timestamp)
        if dateText.isEmpty {
            return durationText
        }
        return "\(dateText) • \(durationText)"
    }

    private func dueDateLabel(for date: Date) -> String {
        "Due \(dueDateFormatter.string(from: date))"
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .activity:
            return "No activity yet"
        case .appointments:
            return "No appointments found"
        case .followUp:
            return "No follow-ups pending"
        }
    }

    private func iconName(for filter: ActivityFeedFilter) -> String {
        switch filter {
        case .activity:
            return "figure.walk"
        case .appointments:
            return "calendar"
        case .followUp:
            return "arrow.uturn.right.circle"
        }
    }

    private func symbolName(for kind: ActivityFeedKind) -> String {
        switch kind {
        case .session:
            return "figure.walk"
        case .appointment:
            return "calendar.badge.clock"
        case .followUp:
            return "arrow.uturn.right.circle.fill"
        }
    }

    private func tintColor(for kind: ActivityFeedKind) -> Color {
        switch kind {
        case .session:
            return .flyrPrimary
        case .appointment:
            return .purple
        case .followUp:
            return .orange
        }
    }

    private func formatSessionDuration(_ seconds: TimeInterval?) -> String {
        let totalSeconds = Int((seconds ?? 0).rounded())
        guard totalSeconds > 0 else { return "0 min" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(max(1, minutes)) min"
    }

    private func openSessionDetail(for item: ActivityFeedItem) {
        guard item.kind == .session, let sessionId = item.sessionId else {
            showSessionError = true
            return
        }
        loadingSessionItemId = item.id
        Task {
            do {
                let session = try await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionId)
                await MainActor.run {
                    loadingSessionItemId = nil
                    guard let session else {
                        showSessionError = true
                        return
                    }
                    selectedSessionDetail = ActivitySessionDetailItem(id: sessionId, session: session)
                }
            } catch {
                await MainActor.run {
                    loadingSessionItemId = nil
                    showSessionError = true
                }
            }
        }
    }

    private func loadItems() async {
        guard let userId = auth.user?.id else {
            errorMessage = "Please sign in to view activity"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            items = try await ActivityFeedService.shared.fetchItems(
                userId: userId,
                workspaceId: workspace.workspaceId,
                includeMembers: false,
                filter: selectedFilter,
                limit: 150
            )
        } catch {
            errorMessage = "Failed to load \(selectedFilter.rawValue.lowercased())"
        }
        isLoading = false
    }

    private var sessionDateFormatter: DateFormatter {
        Self._sessionDateFormatter
    }

    private var dueDateFormatter: DateFormatter {
        Self._dueDateFormatter
    }

    private static let _sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let _dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d, h:mm a")
        return formatter
    }()
}

private struct ActivitySessionDetailItem: Identifiable {
    let id: UUID
    let session: SessionRecord
}

struct ActivityFeedEditSheet: View {
    let item: ActivityFeedItem
    let requiresAddress: Bool
    let onSave: (String, String, Date, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var address: String
    @State private var dueDate: Date
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    init(
        item: ActivityFeedItem,
        requiresAddress: Bool = true,
        onSave: @escaping (String, String, Date, String?) async throws -> Void
    ) {
        self.item = item
        self.requiresAddress = requiresAddress
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _address = State(initialValue: item.address ?? item.subtitle.components(separatedBy: " • ").first ?? "")
        _dueDate = State(initialValue: item.dueDate ?? item.timestamp)
        _notes = State(initialValue: item.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.kind == .appointment ? "Edit Appointment" : "Edit Follow Up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.muted)
                        .frame(width: 32, height: 32)
                        .background(Color.bgSecondary.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                TextField("Name", text: $title)
                    .focused($focusedField, equals: .title)
                    .textInputAutocapitalization(.words)
                    .activityEditorFieldStyle()

                TextField("Address", text: $address)
                    .focused($focusedField, equals: .address)
                    .textInputAutocapitalization(.words)
                    .activityEditorFieldStyle()

                DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.text)
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(Color.bgSecondary.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                TextField("Notes", text: $notes, axis: .vertical)
                    .focused($focusedField, equals: .notes)
                    .lineLimit(2...4)
                    .activityEditorFieldStyle(minHeight: 62)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(ActivityEditorSecondaryButtonStyle())
                .disabled(isSaving)

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(ActivityEditorPrimaryButtonStyle())
                .disabled(isSaving || !canSave)
            }
        }
        .padding(18)
        .background(Color.bg.ignoresSafeArea())
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!requiresAddress || !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func save() {
        guard canSave else { return }
        let draftTitle = title
        let draftAddress = address
        let draftDueDate = dueDate
        let draftNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        focusedField = nil
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await onSave(
                    draftTitle,
                    draftAddress,
                    draftDueDate,
                    draftNotes
                )
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Could not save changes."
                }
            }
        }
    }

    private enum Field: Hashable {
        case title
        case address
        case notes
    }
}

private extension View {
    func activityEditorFieldStyle(minHeight: CGFloat = 48) -> some View {
        self
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.text)
            .padding(.horizontal, 12)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(Color.bgSecondary.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ActivityEditorPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(height: 48)
            .background(Color.flyrPrimary.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ActivityEditorSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.text)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.bgSecondary.opacity(configuration.isPressed ? 0.65 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ActivitySessionDetailView: View {
    let session: SessionRecord
    @Environment(\.dismiss) private var dismiss

    private var coordinates: [CLLocationCoordinate2D] {
        session.pathCoordinates
    }

    private var conversationsCount: Int {
        max(0, session.conversations ?? 0)
    }

    private var bodyColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                ActivitySessionBreadcrumbMap(coordinates: coordinates)

                LazyVGrid(columns: bodyColumns, spacing: 10) {
                    ActivitySessionMetricCard(
                        title: "Doors",
                        value: "\(session.doorsCount)",
                        subtitle: String(format: "%.1f/hr", session.doorsPerHour)
                    )
                    ActivitySessionMetricCard(
                        title: "Conversations",
                        value: "\(conversationsCount)",
                        subtitle: formattedPercent(session.conversationsPerDoor) + " of doors"
                    )
                    ActivitySessionMetricCard(
                        title: "Leads",
                        value: "\(session.leadsCreated)",
                        subtitle: formattedPercent(session.leadsPerConversation) + " of conv"
                    )
                    ActivitySessionMetricCard(
                        title: "Distance",
                        value: formattedDistance(session.distance_meters ?? 0),
                        subtitle: String(format: "%.1f completions/km", session.completionsPerKm)
                    )
                    ActivitySessionMetricCard(
                        title: "Field Time",
                        value: formattedDuration(session.durationSeconds),
                        subtitle: session.end_time == nil ? "Active session" : "Completed session"
                    )
                    ActivitySessionMetricCard(
                        title: "Appointments",
                        value: "\(session.appointmentsCount)",
                        subtitle: formattedPercent(session.appointmentsPerConversation) + " of conv"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Session Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.end_time == nil ? "Active Session" : "Completed Session")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.text)
            Text(sessionTimeRange)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.muted)
        }
    }

    private var sessionTimeRange: String {
        let start = Self.timeFormatter.string(from: session.start_time)
        guard let end = session.end_time else {
            return "\(Self.dateFormatter.string(from: session.start_time)) at \(start)"
        }
        return "\(Self.dateFormatter.string(from: session.start_time)) • \(start)-\(Self.timeFormatter.string(from: end))"
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private func formattedPercent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, value) * 100)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")
        return formatter
    }()
}

private struct ActivitySessionMetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.muted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary.opacity(0.82))
        )
    }
}

private struct ActivitySessionBreadcrumbMap: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.flyrPrimary)
                Text("GPS Breadcrumb")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.text)
                Spacer()
                Text("\(coordinates.count) points")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.muted)
            }

            if coordinates.count >= 2 {
                ActivitySessionBreadcrumbMapboxView(coordinates: coordinates)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.muted)
                    Text("No GPS breadcrumb captured for this session.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.bgSecondary.opacity(0.82))
                )
            }
        }
    }
}

private struct ActivitySessionBreadcrumbMapboxView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    private let routeSourceId = "activity-session-breadcrumb-route-source"
    private let routeLayerId = "activity-session-breadcrumb-route-layer"

    func makeUIView(context: Context) -> MapView {
        let mapView = DisplayLinkRecoveringMapView(frame: .zero)
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .adaptive
        context.coordinator.mapView = mapView
        if let map = mapView.mapboxMap {
            MapTheme.loadBlueStandardLightStyle(on: map)
        }
        context.coordinator.setupWhenStyleLoads(mapView: mapView, coordinates: coordinates)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.updateRoute(with: coordinates)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(routeSourceId: routeSourceId, routeLayerId: routeLayerId)
    }

    @MainActor
    final class Coordinator {
        private let routeSourceId: String
        private let routeLayerId: String
        weak var mapView: MapView?
        private var isSetup = false
        private var hasFramedRoute = false
        private var styleLoadedObserver: AnyCancelable?

        init(routeSourceId: String, routeLayerId: String) {
            self.routeSourceId = routeSourceId
            self.routeLayerId = routeLayerId
        }

        func setupWhenStyleLoads(mapView: MapView, coordinates: [CLLocationCoordinate2D]) {
            guard let map = mapView.mapboxMap else { return }
            if map.isStyleLoaded {
                setup(mapView: mapView)
                updateRoute(with: coordinates)
            } else {
                styleLoadedObserver = map.onStyleLoaded.observeNext { [weak self, weak mapView] _ in
                    guard let self, let mapView else { return }
                    self.setup(mapView: mapView)
                    self.updateRoute(with: coordinates)
                }
            }
        }

        private func setup(mapView: MapView) {
            guard !isSetup, let map = mapView.mapboxMap else { return }
            isSetup = true

            do {
                var source = GeoJSONSource(id: routeSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                var lineLayer = LineLayer(id: routeLayerId, source: routeSourceId)
                lineLayer.lineColor = .constant(StyleColor(.systemRed))
                lineLayer.lineWidth = .constant(5.0)
                lineLayer.lineOpacity = .constant(0.92)
                lineLayer.lineJoin = .constant(.round)
                lineLayer.lineCap = .constant(.round)
                try map.addLayer(lineLayer)
            } catch {
                print("[ActivitySessionBreadcrumbMap] Failed to setup route layer: \(error)")
            }
        }

        func updateRoute(with coordinates: [CLLocationCoordinate2D]) {
            let validCoordinates = coordinates.filter(CLLocationCoordinate2DIsValid)
            guard let map = mapView?.mapboxMap,
                  map.sourceExists(withId: routeSourceId) else { return }

            let features: [Feature]
            if validCoordinates.count >= 2 {
                let line = validCoordinates.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                features = [Feature(geometry: .lineString(LineString(line)))]
            } else {
                features = []
            }
            map.updateGeoJSONSource(withId: routeSourceId, geoJSON: .featureCollection(FeatureCollection(features: features)))

            guard validCoordinates.count >= 2 else { return }
            if !hasFramedRoute {
                hasFramedRoute = true
                frameRoute(coordinates: validCoordinates)
            }
        }

        private func frameRoute(coordinates: [CLLocationCoordinate2D]) {
            guard let mapView else { return }
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
            case ..<0.001: zoom = 17.0
            case ..<0.003: zoom = 16.0
            case ..<0.008: zoom = 15.0
            case ..<0.02: zoom = 14.0
            case ..<0.05: zoom = 13.0
            case ..<0.12: zoom = 12.0
            default: zoom = 11.0
            }

            mapView.camera.ease(
                to: CameraOptions(center: center, zoom: zoom, bearing: 0, pitch: 0),
                duration: 0.8
            )
            if let map = mapView.mapboxMap {
                MapTheme.applyLightModeShadowPolicy(to: map, pitch: 0)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
