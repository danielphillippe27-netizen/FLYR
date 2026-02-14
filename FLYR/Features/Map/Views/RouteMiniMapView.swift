import SwiftUI
import CoreLocation

/// Orange route squiggle in a fixed square box; coordinates normalized to fit with padding. No map, no cards.
struct RouteMiniMapView: View {
    let points: [CLLocationCoordinate2D]
    var boxSize: CGFloat = 220
    var lineWidth: CGFloat = 4
    var strokeColor: Color = Color(red: 0.98, green: 0.36, blue: 0.14)

    var body: some View {
        ZStack {
            if points.count >= 2 {
                RouteSquiggleShape(coordinates: points)
                    .stroke(strokeColor, lineWidth: lineWidth)
                    .frame(width: boxSize, height: boxSize)
            } else {
                Text("No route recorded")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: boxSize, height: boxSize)
            }
        }
        .frame(width: boxSize, height: boxSize)
    }
}

private struct RouteSquiggleShape: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count >= 2 else { return Path() }
        let padding: CGFloat = 16
        let (minLat, maxLat, minLon, maxLon) = bounds
        var width = maxLon - minLon
        var height = maxLat - minLat
        if width <= 0 { width = 0.0002 }
        if height <= 0 { height = 0.0002 }
        let drawW = rect.width - padding * 2
        let drawH = rect.height - padding * 2
        var path = Path()
        for (i, coord) in coordinates.enumerated() {
            let x = padding + CGFloat((coord.longitude - minLon) / width) * drawW
            let y = rect.height - padding - CGFloat((coord.latitude - minLat) / height) * drawH
            let point = CGPoint(x: x, y: y)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private var bounds: (Double, Double, Double, Double) {
        guard !coordinates.isEmpty else { return (0, 0, 0, 0) }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let pad = 0.0002
        return (minLat - pad, maxLat + pad, minLon - pad, maxLon + pad)
    }
}

#Preview("With route") {
    RouteMiniMapView(
        points: [
            CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            CLLocationCoordinate2D(latitude: 43.652, longitude: -79.382),
            CLLocationCoordinate2D(latitude: 43.651, longitude: -79.385),
            CLLocationCoordinate2D(latitude: 43.653, longitude: -79.387),
        ]
    )
    .background(Color.black.opacity(0.3))
}

#Preview("No route") {
    RouteMiniMapView(points: [])
    .background(Color.black.opacity(0.3))
}
