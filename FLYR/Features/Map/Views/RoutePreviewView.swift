import SwiftUI
import MapboxMaps

struct RoutePreviewView: View {
    let route: OptimizedRoute
    let goalType: GoalType
    var goalAmount: Int? = nil
    let campaignId: UUID?
    var sessionNotes: String? = nil
    var showCancelButton: Bool = true
    
    @Environment(\.dismiss) private var dismiss
    @State private var showWaypointList: Bool = false
    
    var body: some View {
        ZStack {
            // Map
            RoutePreviewMapView(route: route)
                .ignoresSafeArea()
            
            // Top stats card
            VStack {
                routeStatsCard
                    .padding()
                
                Spacer()
            }
            
            // Bottom sheet with waypoint list
            VStack {
                Spacer()
                
                if showWaypointList {
                    waypointListSheet
                        .transition(.move(edge: .bottom))
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        HapticManager.light()
                        withAnimation {
                            showWaypointList.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: showWaypointList ? "chevron.down" : "list.bullet")
                            Text(showWaypointList ? "Hide" : "View Stops")
                        }
                        .font(.flyrSubheadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    }
                    
                    Button {
                        HapticManager.medium()
                        startSession()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Session")
                        }
                        .font(.flyrHeadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    }
                }
                .padding()
                .background(Color(.systemBackground).opacity(0.95))
            }
        }
        .navigationTitle("Route Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    // MARK: - Route Stats Card
    
    private var routeStatsCard: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(route.formattedDistance)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.flyrHeadline)
                
                Text("Distance")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Label("\(route.formattedDuration)", systemImage: "clock")
                    .font(.flyrHeadline)
                
                Text("Estimated Time")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Label("\(route.stopCount)", systemImage: "house.fill")
                    .font(.flyrHeadline)
                
                Text("Stops")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(radius: 8)
        )
    }
    
    // MARK: - Waypoint List Sheet
    
    private var waypointListSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Route Stops")
                    .font(.flyrHeadline)
                Spacer()
                Text("\(route.stopCount) homes")
                    .font(.flyrSubheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            
            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(route.waypoints) { waypoint in
                        waypointRow(waypoint)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(radius: 8)
    }
    
    private func waypointRow(_ waypoint: RouteWaypoint) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Number badge
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 32, height: 32)
                    
                    Text("\(waypoint.orderIndex + 1)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
                
                // Address
                VStack(alignment: .leading, spacing: 2) {
                    Text(waypoint.address)
                        .font(.flyrSubheadline)
                        .lineLimit(2)
                    
                    if let eta = waypoint.estimatedArrivalTime {
                        Text(eta, style: .time)
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            
            Divider()
                .padding(.leading, 56)
        }
    }
    
    // MARK: - Actions
    
    private func startSession() {
        HapticManager.success()
        SessionManager.shared.sessionNotes = sessionNotes
        SessionManager.shared.start(
            goalType: goalType,
            goalAmount: goalAmount ?? route.stopCount,
            route: route,
            campaignId: campaignId
        )
        
        // Dismiss all the way back to the map
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            // Find navigation controller and pop to root
            if let navController = findNavigationController(from: rootVC) {
                navController.popToRootViewController(animated: true)
            }
        }
    }
    
    private func findNavigationController(from viewController: UIViewController) -> UINavigationController? {
        if let nav = viewController as? UINavigationController {
            return nav
        }
        
        for child in viewController.children {
            if let nav = findNavigationController(from: child) {
                return nav
            }
        }
        
        if let presented = viewController.presentedViewController {
            return findNavigationController(from: presented)
        }
        
        return nil
    }
}

// MARK: - Route Preview Map

struct RoutePreviewMapView: UIViewRepresentable {
    let route: OptimizedRoute
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Configure map
        mapView.mapboxMap.setCamera(to: CameraOptions(
            zoom: 14,
            pitch: 45
        ))
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Set up map style and layers
        mapView.mapboxMap.styleURI = .init(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")
        
        // Wait for style to load, then add route
        mapView.mapboxMap.onStyleLoaded.observe { _ in
            self.addRouteLayer(to: mapView)
            self.addWaypointAnnotations(to: mapView)
            self.frameRoute(in: mapView)
        }.store(in: &context.coordinator.cancellables)
    }
    
    private func addRouteLayer(to mapView: MapView) {
        guard !route.allCoordinates.isEmpty else { return }
        
        // Create line string from route coordinates
        let lineString = LineString(route.allCoordinates)
        
        // Create GeoJSON source
        var source = GeoJSONSource(id: "route-source")
        source.data = .geometry(.lineString(lineString))
        
        // Add source
        try? mapView.mapboxMap.addSource(source)
        
        // Create line layer
        var lineLayer = LineLayer(id: "route-line-layer", source: "route-source")
        lineLayer.lineColor = .constant(StyleColor(.blue))
        lineLayer.lineWidth = .constant(4.0)
        lineLayer.lineJoin = .constant(.round)
        lineLayer.lineCap = .constant(.round)
        
        // Add layer
        try? mapView.mapboxMap.addLayer(lineLayer)
    }
    
    private func addWaypointAnnotations(to mapView: MapView) {
        var annotations: [PointAnnotation] = []
        
        for waypoint in route.waypoints {
            var annotation = PointAnnotation(coordinate: waypoint.coordinate)
            annotation.textField = "\(waypoint.orderIndex + 1)"
            annotation.textColor = StyleColor(.white)
            annotation.textSize = 12
            annotation.textHaloColor = StyleColor(.blue)
            annotation.textHaloWidth = 1
            annotation.iconImage = "marker-\(waypoint.orderIndex + 1)"
            annotations.append(annotation)
        }
        
        // Add annotations using point annotation manager
        let pointAnnotationManager = mapView.annotations.makePointAnnotationManager()
        pointAnnotationManager.annotations = annotations
    }
    
    private func frameRoute(in mapView: MapView) {
        guard !route.allCoordinates.isEmpty else { return }
        
        // Calculate bounding box
        let coordinates = route.allCoordinates
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else { return }
        
        let southwest = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
        let northeast = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        let bounds = CoordinateBounds(southwest: southwest, northeast: northeast)
        
        // Frame camera to bounds with padding
        let cameraOptions = CameraOptions(
            center: bounds.center,
            padding: UIEdgeInsets(top: 100, left: 50, bottom: 250, right: 50),
            zoom: nil,
            bearing: nil,
            pitch: nil
        )
        
        mapView.camera.ease(to: cameraOptions, duration: 0.8)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var cancellables: Set<AnyCancellable> = []
    }
}

// MARK: - Helper Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Import Combine for AnyCancellable
import Combine
