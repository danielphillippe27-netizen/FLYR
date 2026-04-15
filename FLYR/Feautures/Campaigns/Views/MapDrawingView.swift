import SwiftUI
import CoreLocation

struct MapDrawingView: View {
    /// Optional initial map center (e.g. user location) for camera only.
    let initialCenter: CLLocationCoordinate2D?
    @Environment(\.colorScheme) private var colorScheme

    @State private var polygonVertices: [CLLocationCoordinate2D] = []
    @State private var useSatellite: Bool = true
    @StateObject private var locationManager = LocationManager()

    let onPolygonDone: ([CLLocationCoordinate2D]) -> Void
    /// When set, shows "Create Campaign" button; called with closed polygon then dismisses.
    var onCreateCampaign: (([CLLocationCoordinate2D]) -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(initialCenter: CLLocationCoordinate2D? = nil,
         onPolygonDone: @escaping ([CLLocationCoordinate2D]) -> Void,
         onCreateCampaign: (([CLLocationCoordinate2D]) -> Void)? = nil) {
        self.initialCenter = initialCenter
        self.onPolygonDone = onPolygonDone
        self.onCreateCampaign = onCreateCampaign
    }

    /// Distance in meters within which a tap is considered "on the first point" to close the polygon.
    private static let closePolygonDistanceMeters: CLLocationDistance = 25

    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    private var mapCenter: CLLocationCoordinate2D {
        if let first = polygonVertices.first {
            return first
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
                    onTap: handleTap,
                    onMoveVertex: { index, newCoord in
                        guard index >= 0, index < polygonVertices.count else { return }
                        var updated = polygonVertices
                        updated[index] = newCoord
                        polygonVertices = updated
                    }
                )
                .ignoresSafeArea(edges: .top)

                // Floating controls over the map
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.leading, 12)

                    Spacer()

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
                        HStack(spacing: 4) {
                            Image(systemName: useSatellite ? "globe.americas.fill" : "map")
                            Text(useSatellite ? "Satellite" : "Map")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Tap map to add points. Drag a red point to move it. Tap first point again to close polygon.")
                    .font(.flyrSubheadline)
                    .foregroundStyle(.primary.opacity(0.9))

                HStack(spacing: 12) {
                    if !polygonVertices.isEmpty {
                        Button("Clear") {
                            polygonVertices.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if let onCreateCampaign = onCreateCampaign, polygonVertices.count >= 3 {
                        Button("Create Campaign") {
                            confirmAndCreateCampaign(trigger: onCreateCampaign)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Draw on Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            locationManager.requestLocation()
        }
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
        onPolygonDone(closed)
        dismiss()
    }

    /// Build closed ring, call onCreateCampaign, then dismiss (for "Create Campaign" from drawing screen).
    private func confirmAndCreateCampaign(trigger: ([CLLocationCoordinate2D]) -> Void) {
        guard polygonVertices.count >= 3 else { return }
        var closed = polygonVertices
        if closed.first != closed.last, let first = closed.first {
            closed.append(first)
        }
        trigger(closed)
        dismiss()
    }
}
