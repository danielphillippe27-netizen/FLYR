import SwiftUI
import CoreLocation

/// Homes share card: map snapshot (live campaign capture or Mapbox static), optional home markers, Strava-style stats.
struct SessionHomesShareCardView: View {
    let data: SessionSummaryData
    var forExport: Bool = false
    var darkCard: Bool = false
    var backgroundSnapshot: UIImage? = nil
    /// Green home cubes. Off when using a live campaign bitmap (already shows session art) or demo share-card mode.
    var showVectorOverlay: Bool = true

    private var cornerRadius: CGFloat { forExport ? 0 : 24 }
    private var horizontalPadding: CGFloat { forExport ? 56 : 20 }
    private var headingFont: Font { .system(size: forExport ? 80 : 32, weight: .heavy) }
    private var flyrLogoWidth: CGFloat { forExport ? 560 : 180 }
    private var flyrExportWordmarkFont: Font { .system(size: 216, weight: .black) }
    private var statValueFont: Font { .system(size: forExport ? 56 : 22, weight: .bold) }
    private var statLabelFont: Font { .system(size: forExport ? 28 : 12, weight: .medium) }
    private var logoTopPadding: CGFloat { forExport ? 72 : 18 }
    private var logoTrailingPadding: CGFloat { forExport ? 48 : 16 }

    private var sessionHeadingTitle: String {
        guard let start = data.startTime else { return "Session" }
        let hour = Calendar.current.component(.hour, from: start)
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    private var effectiveVectorOverlay: Bool {
        showVectorOverlay && !data.isDemoSession
    }

    var body: some View {
        ZStack {
            cardBackground

            ZStack {
                VisitedHomesMapArtwork(
                    routeSegments: data.displayRouteSegments,
                    completedHomes: data.completedHomeCoordinates,
                    backgroundSnapshot: backgroundSnapshot,
                    showVectorOverlay: effectiveVectorOverlay
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.2),
                        Color.black.opacity(0.65),
                        Color.black.opacity(0.92),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: forExport ? 20 : 10) {
                        Text(sessionHeadingTitle)
                            .font(headingFont)
                            .foregroundColor(.white)

                        if !routeSubtitle.isEmpty {
                            Text(routeSubtitle)
                                .font(.system(size: forExport ? 30 : 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.78))
                        }

                        HStack(alignment: .top, spacing: forExport ? 32 : 12) {
                            stravaStatColumn(label: "Doors", value: "\(data.doorsCount)")
                            stravaStatColumn(label: "Distance", value: data.formattedDistance)
                            stravaStatColumn(label: "Time", value: data.formattedTimeStrava)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, forExport ? 88 : 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                flyrLogoOverlay
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var flyrLogoOverlay: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Group {
                    if forExport {
                        Text("FLYR")
                            .font(flyrExportWordmarkFont)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                    } else {
                        Image("FLYRLogoWide")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundColor(.white)
                    }
                }
                .frame(width: flyrLogoWidth, alignment: .trailing)
                .padding(.top, logoTopPadding)
                .padding(.trailing, logoTrailingPadding)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

    private var routeSubtitle: String {
        let homesCount = data.completedHomeCoordinates.count
        if homesCount > 0 {
            return "\(homesCount) home\(homesCount == 1 ? "" : "s") completed"
        }
        return ""
    }

    private var cardBackground: some View {
        Group {
            if forExport {
                Color.clear
            } else if darkCard {
                Color(white: 0.12)
            } else {
                CheckeredBackground(
                    squareSize: 24,
                    color1: .gray.opacity(0.35),
                    color2: .gray.opacity(0.2)
                )
            }
        }
    }

    private func stravaStatColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: forExport ? 10 : 5) {
            Text(label)
                .font(statLabelFont)
                .foregroundColor(.white.opacity(0.82))
            Text(value)
                .font(statValueFont)
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VisitedHomesMapArtwork: View {
    let routeSegments: [[CLLocationCoordinate2D]]
    let completedHomes: [CLLocationCoordinate2D]
    let backgroundSnapshot: UIImage?
    var showVectorOverlay: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let minSide = min(proxy.size.width, proxy.size.height)
            let pad = max(14, minSide * 0.03)
            let projection = ActivityMapProjection(
                routeSegments: routeSegments,
                homeCoordinates: completedHomes,
                size: proxy.size,
                padding: pad
            )
            ZStack {
                if let backgroundSnapshot {
                    Image(uiImage: backgroundSnapshot)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    // Dark map-style placeholder (matches Strava card when snapshot is still loading or unavailable).
                    ShareCardMapFallbackBackground(size: proxy.size)
                }

                if showVectorOverlay {
                    ForEach(Array(completedHomes.enumerated()), id: \.offset) { item in
                        let point = projection.project(item.element)
                        CompletedHomeCubeMarker(side: max(9, minSide * 0.034))
                            .position(point)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Dark, map-like backdrop when the Mapbox static snapshot is not ready yet (avoids the light “poster” look).
private struct ShareCardMapFallbackBackground: View {
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                var grid = Path()
                let spacing: CGFloat = max(36, min(w, h) * 0.055)
                var x: CGFloat = -spacing
                while x < w + spacing {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x + h * 0.08, y: h))
                    x += spacing
                }
                var y: CGFloat = -spacing
                while y < h + spacing {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: w, y: y + w * 0.02))
                    y += spacing * 1.15
                }
                context.stroke(grid, with: .color(.white.opacity(0.045)), lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Small isometric “completed home” marker (bright green cube + white edge) matching the original share card.
private struct CompletedHomeCubeMarker: View {
    let side: CGFloat

    private var cubeFont: Font { .system(size: side, weight: .regular, design: .rounded) }

    var body: some View {
        ZStack {
            Image(systemName: "cube.fill")
                .font(cubeFont)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 0.5)
            Image(systemName: "cube.fill")
                .font(.system(size: max(side - 2.2, side * 0.78), weight: .regular, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.38, green: 0.98, blue: 0.62),
                            Color(red: 0.12, green: 0.72, blue: 0.40),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: side * 1.2, height: side * 1.2)
    }
}

private struct ActivityMapProjection {
    let size: CGSize
    private let minLat: Double
    private let maxLat: Double
    private let minLon: Double
    private let maxLon: Double
    private let padding: CGFloat

    init(
        routeSegments: [[CLLocationCoordinate2D]] = [],
        homeCoordinates: [CLLocationCoordinate2D],
        size: CGSize,
        padding: CGFloat
    ) {
        self.size = size
        self.padding = padding

        let valid: (CLLocationCoordinate2D) -> Bool = { CLLocationCoordinate2DIsValid($0) }
        let homes = homeCoordinates.filter(valid)
        let routePoints = routeSegments.flatMap { $0 }.filter(valid)
        let boundsPoints = routePoints + homes

        guard !boundsPoints.isEmpty else {
            minLat = 43.65
            maxLat = 43.651
            minLon = -79.38
            maxLon = -79.379
            return
        }

        var rMinLat = boundsPoints.map(\.latitude).min()!
        var rMaxLat = boundsPoints.map(\.latitude).max()!
        var rMinLon = boundsPoints.map(\.longitude).min()!
        var rMaxLon = boundsPoints.map(\.longitude).max()!

        let minSpan: Double = 0.00022
        if rMaxLat - rMinLat < minSpan {
            let mid = (rMinLat + rMaxLat) / 2
            rMinLat = mid - minSpan / 2
            rMaxLat = mid + minSpan / 2
        }
        if rMaxLon - rMinLon < minSpan {
            let mid = (rMinLon + rMaxLon) / 2
            rMinLon = mid - minSpan / 2
            rMaxLon = mid + minSpan / 2
        }

        let latPad = max((rMaxLat - rMinLat) * 0.06, minSpan * 0.045)
        let lonPad = max((rMaxLon - rMinLon) * 0.06, minSpan * 0.045)
        minLat = rMinLat - latPad
        maxLat = rMaxLat + latPad
        minLon = rMinLon - lonPad
        maxLon = rMaxLon + lonPad
    }

    func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        let width = max(maxLon - minLon, 0.0001)
        let height = max(maxLat - minLat, 0.0001)
        let drawWidth = max(size.width - padding * 2, 1)
        let drawHeight = max(size.height - padding * 2, 1)
        let x = padding + CGFloat((coordinate.longitude - minLon) / width) * drawWidth
        let y = size.height - padding - CGFloat((coordinate.latitude - minLat) / height) * drawHeight
        return CGPoint(x: x, y: y)
    }
}

#Preview {
    SessionHomesShareCardView(
        data: SessionSummaryData(
            distance: 9190,
            time: 3120,
            goalType: .knocks,
            goalAmount: 50,
            pathCoordinates: [
                CLLocationCoordinate2D(latitude: 43.6500, longitude: -79.3800),
                CLLocationCoordinate2D(latitude: 43.6514, longitude: -79.3812),
                CLLocationCoordinate2D(latitude: 43.6530, longitude: -79.3824),
                CLLocationCoordinate2D(latitude: 43.6548, longitude: -79.3811),
                CLLocationCoordinate2D(latitude: 43.6563, longitude: -79.3830),
            ],
            renderedPathSegments: [[
                CLLocationCoordinate2D(latitude: 43.6500, longitude: -79.3800),
                CLLocationCoordinate2D(latitude: 43.6516, longitude: -79.3814),
                CLLocationCoordinate2D(latitude: 43.6536, longitude: -79.3827),
            ], [
                CLLocationCoordinate2D(latitude: 43.6536, longitude: -79.3827),
                CLLocationCoordinate2D(latitude: 43.6551, longitude: -79.3818),
                CLLocationCoordinate2D(latitude: 43.6563, longitude: -79.3830),
            ]],
            completedHomeCoordinates: [
                CLLocationCoordinate2D(latitude: 43.6514, longitude: -79.3812),
                CLLocationCoordinate2D(latitude: 43.6548, longitude: -79.3811),
                CLLocationCoordinate2D(latitude: 43.6563, longitude: -79.3830),
            ],
            completedCount: 12,
            conversationsCount: 5,
            startTime: Date()
        ),
        darkCard: true
    )
}
