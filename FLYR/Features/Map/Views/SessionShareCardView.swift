import SwiftUI
import CoreLocation

/// Which three metrics to show on the share card.
enum ShareCardMetrics {
    /// DOORS, DISTANCE, TIME
    case doorsDistanceTime
    /// DOORS, CONVERSATIONS, TIME
    case doorsConvoTime
}

/// Full-screen Strava-style share card: transparent, checkered, or dark card background; three metrics (variant), route squiggle, brand.
/// Use forExport: true when rendering to PNG (transparent). Use darkCard: true when showing on black (summary screen).
struct SessionShareCardView: View {
    let data: SessionSummaryData
    /// When true, use clear background for 1080×1920 PNG export.
    var forExport: Bool = false
    /// When true, use dark gray card background (e.g. on black summary screen). When false and !forExport, use checkered.
    var darkCard: Bool = false
    /// Which metric set to display. Default: doorsDistanceTime for in-app and variant A PNG.
    var metrics: ShareCardMetrics = .doorsDistanceTime

    private var metricSpacing: CGFloat { forExport ? 40 : 22 }
    private var labelFont: Font { Font.system(size: forExport ? 36 : 13, weight: .medium) }
    private var valueFont: Font { Font.system(size: forExport ? 96 : 34, weight: .bold) }
    private var logoHeight: CGFloat { forExport ? 100 : 50 }
    private var topSpacer: CGFloat { forExport ? 48 : 20 }
    private var bottomSpacer: CGFloat { forExport ? 8 : 4 }
    private var routeBoxSize: CGFloat { forExport ? 120 : 100 }

    var body: some View {
        ZStack {
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

            VStack(spacing: 0) {
                // When darkCard (in-app summary), use fixed spacing so the card has intrinsic height and the logo is always visible. When forExport, use flexible Spacers to fill 1080×1920.
                if forExport {
                    Spacer(minLength: topSpacer)
                } else {
                    Spacer().frame(height: topSpacer)
                }

                // Row 1: Doors
                StravaMetricRow(label: "Doors", value: "\(data.doorsCount)", labelFont: labelFont, valueFont: valueFont, spacing: forExport ? 16 : 6)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)

                Spacer().frame(height: metricSpacing)

                // Row 2: depends on variant
                switch metrics {
                case .doorsDistanceTime:
                    StravaMetricRow(label: "Distance", value: data.formattedDistance, labelFont: labelFont, valueFont: valueFont, spacing: forExport ? 16 : 6)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity)
                case .doorsConvoTime:
                    StravaMetricRow(label: "Conversations", value: "\(data.conversations)", labelFont: labelFont, valueFont: valueFont, spacing: forExport ? 16 : 6)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity)
                }

                Spacer().frame(height: metricSpacing)

                // Row 3: depends on variant
                switch metrics {
                case .doorsDistanceTime:
                    StravaMetricRow(label: "Time", value: data.formattedTimeStrava, labelFont: labelFont, valueFont: valueFont, spacing: forExport ? 16 : 6)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity)
                case .doorsConvoTime:
                    StravaMetricRow(label: "Time", value: data.formattedTimeStrava, labelFont: labelFont, valueFont: valueFont, spacing: forExport ? 16 : 6)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity)
                }

                Spacer().frame(height: metricSpacing)

                // Route squiggle
                RouteMiniMapView(points: data.pathCoordinates, boxSize: routeBoxSize)
                    .padding(.top, forExport ? 8 : 4)
                    .padding(.bottom, forExport ? 2 : 4)

                // Small fixed gap so FLYR sits right under the route (no big flexible gap)
                if forExport {
                    Spacer().frame(height: 16)
                } else {
                    Spacer().frame(height: 12)
                }

                // FLYR logo at bottom - use text for export since SVG may not render
                if forExport {
                    Text("FLYR")
                        .font(.system(size: 88, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 48)
                        .padding(.bottom, 32)
                } else {
                    Image("FLYRLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: logoHeight)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                // Bottom flexible spacer for export so the whole block is vertically centered
                if forExport {
                    Spacer(minLength: topSpacer)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: forExport ? .infinity : nil)
            .fixedSize(horizontal: false, vertical: !forExport)
        }
        .foregroundColor(.white)
    }
}

private struct StravaMetricRow: View {
    let label: String
    let value: String
    var labelFont: Font = Font.system(size: 13, weight: .medium)
    var valueFont: Font = Font.system(size: 34, weight: .bold)
    var spacing: CGFloat = 6
    var valueIcon: String? = nil

    var body: some View {
        VStack(spacing: spacing) {
            Text(label)
                .font(labelFont)
                .foregroundColor(.white.opacity(0.9))
            
            HStack(spacing: forExport ? 16 : 8) {
                Text(value)
                    .font(valueFont)
                    .foregroundColor(.white)
                
                if let icon = valueIcon {
                    Image(systemName: icon)
                        .font(.system(size: forExport ? 56 : 28, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var forExport: Bool {
        labelFont == Font.system(size: 36, weight: .medium)
    }
}

#Preview {
    SessionShareCardView(
        data: SessionSummaryData(
            distance: 14_000,
            time: 4260,
            goalType: .knocks,
            goalAmount: 50,
            pathCoordinates: [
                CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
                CLLocationCoordinate2D(latitude: 43.652, longitude: -79.382),
                CLLocationCoordinate2D(latitude: 43.651, longitude: -79.385),
            ],
            completedCount: 12,
            conversationsCount: 5,
            startTime: Date()
        )
    )
}
