import SwiftUI
import CoreLocation

struct MapDrawingView: View {
    /// Optional initial map center (e.g. user location) for camera only.
    let initialCenter: CLLocationCoordinate2D?
    @Environment(\.colorScheme) private var colorScheme

    @State private var polygonVertices: [CLLocationCoordinate2D] = []
    @State private var useSatellite: Bool = true
    @State private var isDrawingEnabled: Bool = true
    @State private var showSearch = false
    @State private var searchedCenter: CLLocationCoordinate2D?
    @State private var searchedCenterLabel = ""
    @State private var cameraFocusID = 0
    @StateObject private var auto = UseAddressAutocomplete()
    @StateObject private var locationManager = LocationManager()

    let onPolygonDone: ([CLLocationCoordinate2D]) -> Void
    /// When set, shows "Create Campaign" button; called with closed polygon then dismisses.
    var onCreateCampaign: (([CLLocationCoordinate2D]) -> Void)?
    var dismissOnPolygonDone: Bool
    var dismissOnCreateCampaign: Bool
    var showsBottomInstructions: Bool

    @Environment(\.dismiss) private var dismiss

    init(initialCenter: CLLocationCoordinate2D? = nil,
         onPolygonDone: @escaping ([CLLocationCoordinate2D]) -> Void,
         onCreateCampaign: (([CLLocationCoordinate2D]) -> Void)? = nil,
         dismissOnPolygonDone: Bool = true,
         dismissOnCreateCampaign: Bool = true,
         showsBottomInstructions: Bool = true) {
        self.initialCenter = initialCenter
        self.onPolygonDone = onPolygonDone
        self.onCreateCampaign = onCreateCampaign
        self.dismissOnPolygonDone = dismissOnPolygonDone
        self.dismissOnCreateCampaign = dismissOnCreateCampaign
        self.showsBottomInstructions = showsBottomInstructions
    }

    /// Distance in meters within which a tap is considered "on the first point" to close the polygon.
    private static let closePolygonDistanceMeters: CLLocationDistance = 25

    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    private var mapCenter: CLLocationCoordinate2D {
        if let first = polygonVertices.first {
            return first
        }
        if let searchedCenter {
            return searchedCenter
        }
        // Prefer explicit seed (optional address / parent-chosen center) over device GPS so "Draw territory" opens on the submitted location.
        if let initialCenter {
            return initialCenter
        }
        return locationManager.currentLocation?.coordinate ?? Self.fallbackCenter
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MapDrawingMapRepresentable(
                    center: mapCenter,
                    startingAddressCoordinate: initialCenter,
                    userLocationCoordinate: locationManager.currentLocation?.coordinate,
                    polygonVertices: polygonVertices,
                    useDarkStyle: colorScheme == .dark,
                    useSatellite: useSatellite,
                    isDrawingEnabled: isDrawingEnabled,
                    cameraFocusCoordinate: searchedCenter,
                    cameraFocusID: cameraFocusID,
                    onTap: handleTap,
                    onMoveVertex: { index, newCoord in
                        guard index >= 0, index < polygonVertices.count else { return }
                        var updated = polygonVertices
                        updated[index] = newCoord
                        polygonVertices = updated
                    }
                )
                .ignoresSafeArea()

                HStack(alignment: .top) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .padding(.top, 12)
                    .padding(.leading, 16)

                    Spacer()

                    rightSideControls
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }

                if showSearch {
                    searchPanel
                        .padding(.top, 62)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack {
                    Spacer()
                    bottomBar
                }
            }
        }
        .navigationTitle("Draw on Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.requestLocation()
        }
    }

    private var rightSideControls: some View {
        VStack(spacing: 10) {
            mapToolButton(
                title: "Draw",
                systemImage: "pencil.tip",
                isSelected: isDrawingEnabled,
                isEnabled: true
            ) {
                isDrawingEnabled.toggle()
            }

            mapToolButton(
                title: "Search",
                systemImage: "magnifyingglass",
                isSelected: showSearch,
                isEnabled: true
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showSearch.toggle()
                }
            }

            mapToolButton(
                title: "Clear",
                systemImage: "trash",
                isSelected: false,
                isEnabled: !polygonVertices.isEmpty
            ) {
                polygonVertices.removeAll()
            }

            Menu {
                Button {
                    useSatellite = false
                } label: {
                    Label("Map", systemImage: "map")
                }
                Button {
                    useSatellite = true
                } label: {
                    Label("Satellite", systemImage: "globe.americas.fill")
                }
            } label: {
                Image(systemName: useSatellite ? "globe.americas.fill" : "map")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func mapToolButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isEnabled ? (isSelected ? .white : .primary) : .secondary)
                .frame(width: 46, height: 46)
                .background(isSelected && isEnabled ? Color.red : Color.clear)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            AddressSearchField(
                auto: auto,
                onPick: { suggestion in
                    focusMap(on: suggestion.coordinate, label: formattedAddress(from: suggestion))
                    auto.clear()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showSearch = false
                    }
                },
                onSubmitQuery: { query in
                    Task { await centerMap(on: query) }
                },
                placeholder: "Search an area or address"
            )

            if !searchedCenterLabel.isEmpty {
                Label(searchedCenterLabel, systemImage: "location.fill")
                    .font(.flyrCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsBottomInstructions {
                Text(isDrawingEnabled ? "Tap map to add points. Drag a red point to move it. Tap first point again to close polygon." : "Move the map, search an area, or tap Draw to continue outlining.")
                    .font(.flyrSubheadline)
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onCreateCampaign = onCreateCampaign {
                Button {
                    confirmAndCreateCampaign(trigger: onCreateCampaign)
                } label: {
                    Text("Create Campaign")
                        .font(.flyrSubheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(polygonVertices.count < 3)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func handleTap(_ coord: CLLocationCoordinate2D) {
        if polygonVertices.count >= 3 {
            let first = polygonVertices[0]
            let firstLocation = CLLocation(latitude: first.latitude, longitude: first.longitude)
            let tapLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if tapLocation.distance(from: firstLocation) <= Self.closePolygonDistanceMeters {
                finishPolygon()
                return
            }
        }
        polygonVertices.append(coord)
    }

    /// Build closed ring and call onPolygonDone, then dismiss.
    private func finishPolygon() {
        guard polygonVertices.count >= 3 else { return }
        var closed = polygonVertices
        if closed.first != closed.last, let first = closed.first {
            closed.append(first)
        }
        polygonVertices = closed
        onPolygonDone(closed)
        if dismissOnPolygonDone {
            dismiss()
        }
    }

    /// Build closed ring, call onCreateCampaign, then dismiss (for "Create Campaign" from drawing screen).
    private func confirmAndCreateCampaign(trigger: ([CLLocationCoordinate2D]) -> Void) {
        guard polygonVertices.count >= 3 else { return }
        var closed = polygonVertices
        if closed.first != closed.last, let first = closed.first {
            closed.append(first)
        }
        trigger(closed)
        if dismissOnCreateCampaign {
            dismiss()
        }
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D, label: String) {
        searchedCenter = coordinate
        searchedCenterLabel = label
        cameraFocusID += 1
    }

    private func centerMap(on query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        do {
            let seed = try await GeoAPI.shared.forwardGeocodeSeed(trimmedQuery)
            await MainActor.run {
                focusMap(on: seed.coordinate, label: trimmedQuery)
                auto.clear()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showSearch = false
                }
            }
        } catch {
            await MainActor.run {
                auto.error = "Could not find \"\(trimmedQuery)\""
            }
        }
    }

    private func formattedAddress(from suggestion: AddressSuggestion) -> String {
        [suggestion.title, suggestion.subtitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
