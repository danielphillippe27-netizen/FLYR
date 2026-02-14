import SwiftUI
import CoreLocation

/// Full-screen Strava-style share card: checkered background, centered metrics (Doors, Distance, Time), route squiggle, brand.
/// No rounded card boxes; white text, bold numbers, small labels.
struct SessionShareCardView: View {
    let data: SessionSummaryData
    private let metricSpacing: CGFloat = 22
    private let labelFont = Font.system(size: 13, weight: .medium)
    private let valueFont = Font.system(size: 34, weight: .bold)

    var body: some View {
        ZStack {
            CheckeredBackground(
                squareSize: 24,
                color1: .gray.opacity(0.35),
                color2: .gray.opacity(0.2)
            )

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Doors
                StravaMetricRow(label: "DOORS", value: "\(data.doorsCount)")
                    .padding(.horizontal)

                Spacer().frame(height: metricSpacing)

                // Distance
                StravaMetricRow(label: "DISTANCE", value: data.formattedDistance)
                    .padding(.horizontal)

                Spacer().frame(height: metricSpacing)

                // Time (above route)
                StravaMetricRow(label: "TIME", value: data.formattedTimeStrava)
                    .padding(.horizontal)

                Spacer().frame(height: metricSpacing)

                // Route squiggle
                RouteMiniMapView(points: data.pathCoordinates)
                    .padding(.vertical, 20)

                Spacer(minLength: 32)

                // Red FLYR logo at bottom
                Image("FLYRLogo")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
                    .foregroundColor(.red)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundColor(.white)
    }
}

private struct StravaMetricRow: View {
    let label: String
    let value: String

    private let labelFont = Font.system(size: 13, weight: .medium)
    private let valueFont = Font.system(size: 34, weight: .bold)

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(labelFont)
                .foregroundColor(.white.opacity(0.9))
            Text(value)
                .font(valueFont)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
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
            startTime: Date()
        )
    )
}
