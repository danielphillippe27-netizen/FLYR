import SwiftUI
import MapboxMaps
import CoreLocation

struct FarmPolygonSelectorView: View {
    @Binding var polygon: [CLLocationCoordinate2D]?
    @Environment(\.dismiss) var dismiss
    
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var mapView: MapView?
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let mapView = mapView {
                    FarmMapboxMapViewRepresentable(mapView: mapView)
                } else {
                    Color(.systemBackground)
                }
                
                VStack {
                    Spacer()
                    
                    HStack {
                        Button("Clear") {
                            points.removeAll()
                        }
                        .disabled(points.isEmpty)
                        
                        Spacer()
                        
                        Text("\(points.count) points")
                            .font(.flyrHeadline)
                        
                        Spacer()
                        
                        Button("Done") {
                            if !points.isEmpty {
                                // Close the polygon
                                var closedPoints = points
                                if closedPoints.first != closedPoints.last {
                                    closedPoints.append(closedPoints.first!)
                                }
                                polygon = closedPoints
                            }
                            dismiss()
                        }
                        .disabled(points.count < 3)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Select Farm Boundary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                initializeMap()
            }
        }
    }
    
    private func initializeMap() {
        let newMapView = MapView(frame: .zero)
        // Configure map with custom light style
        if let map = newMapView.mapboxMap {
            map.loadStyleURI(StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!)
        }
        self.mapView = newMapView
    }
}

struct FarmMapboxMapViewRepresentable: UIViewRepresentable {
    let mapView: MapView
    
    func makeUIView(context: Context) -> MapView {
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        // Updates handled by parent
    }
}

#Preview {
    FarmPolygonSelectorView(polygon: .constant(nil))
}

