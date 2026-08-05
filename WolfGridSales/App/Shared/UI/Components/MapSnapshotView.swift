import SwiftUI
import CoreLocation

/// A SwiftUI component that displays a static map snapshot using Mapbox Static Images API
struct MapSnapshotView: View {
    let center: CLLocationCoordinate2D
    let markers: [MapMarker]
    let height: CGFloat
    
    @StateObject private var mapHook = UseMapSnapshot()
    
    var body: some View {
        Group {
            if mapHook.isLoading {
                // Loading state
                Rectangle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: height)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading map...")
                                .font(.flyrCaption)
                                .foregroundColor(.secondary)
                        }
                    )
            } else if let mapImage = mapHook.mapImage {
                // Map image
                Image(uiImage: mapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: height)
                    .clipped()
            } else {
                // Error state
                Rectangle()
                    .fill(Color.red.opacity(0.1))
                    .frame(height: height)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.flyrTitle2)
                                .foregroundColor(.red)
                            Text("Map unavailable")
                                .font(.flyrCaption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .onAppear {
            print("🗺️ [MAPSNAPSHOT DEBUG] MapSnapshotView appeared")
            print("🗺️ [MAPSNAPSHOT DEBUG] Center: \(center)")
            print("🗺️ [MAPSNAPSHOT DEBUG] Markers: \(markers.count)")
            mapHook.loadMapSnapshot(center: center, markers: markers)
        }
    }
}

#Preview {
    MapSnapshotView(
        center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
        markers: [
            MapMarker(coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38), title: "Campaign", color: "red")
        ],
        height: 240
    )
}
