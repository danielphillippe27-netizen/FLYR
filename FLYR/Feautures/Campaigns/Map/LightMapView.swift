import SwiftUI
import MapboxMaps

/// A minimal Mapbox map view wrapper
struct LightMapView: UIViewRepresentable {
    let height: CGFloat
    let center: CLLocationCoordinate2D
    let zoomLevel: Double
    let onMapLoaded: ((MapView) -> Void)?
    
    init(
        height: CGFloat = 240,
        center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38), // Toronto
        zoomLevel: Double = 12,
        onMapLoaded: ((MapView) -> Void)? = nil
    ) {
        self.height = height
        self.center = center
        self.zoomLevel = zoomLevel
        self.onMapLoaded = onMapLoaded
    }
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Load custom light style
        mapView.mapboxMap.loadStyle(StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!)
        
        mapView.mapboxMap.onNext(event: .mapLoaded) { _ in
            // Center the map when loaded
            let cameraOptions = CameraOptions(
                center: center,
                zoom: zoomLevel
            )
            mapView.mapboxMap.setCamera(to: cameraOptions)
            
            // Call the onMapLoaded callback if provided
            onMapLoaded?(mapView)
        }
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // No updates needed for now
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Text("Map Preview")
            .font(.subheading)
        
        LightMapView(height: 200)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.border, lineWidth: 1)
            )
    }
    .padding()
}
