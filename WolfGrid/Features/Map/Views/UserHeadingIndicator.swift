import CoreLocation
import MapboxMaps
import UIKit

enum UserHeadingConeBand: String, CaseIterable {
    case primary

    var innerRadiusMeters: Double {
        switch self {
        case .primary:
            return 8
        }
    }

    var outerRadiusMeters: Double {
        switch self {
        case .primary:
            return 56
        }
    }

    var color: UIColor {
        switch self {
        case .primary:
            return UIColor(red: 1.0, green: 0.31, blue: 0.27, alpha: 1.0)
        }
    }
}

enum UserHeadingIndicatorRenderer {
    static func featureCollection(
        center: CLLocationCoordinate2D,
        presentationState: MapHeadingPresentationState
    ) -> FeatureCollection {
        guard presentationState.isRenderable,
              let heading = presentationState.heading else {
            return FeatureCollection(features: [])
        }

        let features = UserHeadingConeBand.allCases.map { band -> Feature in
            var feature = Feature(
                geometry: .polygon(
                    makeSector(
                        center: center,
                        heading: heading,
                        spreadDegrees: presentationState.spreadDegrees,
                        band: band
                    )
                )
            )
            feature.properties = [
                "band": .string(band.rawValue),
                "opacity": .number(presentationState.opacity)
            ]
            return feature
        }
        return FeatureCollection(features: features)
    }

    static func styleColor(for band: UserHeadingConeBand) -> StyleColor {
        StyleColor(band.color)
    }

    private static func makeSector(
        center: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        spreadDegrees: CLLocationDirection,
        band: UserHeadingConeBand
    ) -> Polygon {
        let startAngle = heading - (spreadDegrees / 2)
        let endAngle = heading + (spreadDegrees / 2)
        let stepCount = max(12, Int(spreadDegrees / 5))

        var ring: [LocationCoordinate2D] = []
        for step in 0...stepCount {
            let progress = Double(step) / Double(stepCount)
            let angle = startAngle + ((endAngle - startAngle) * progress)
            ring.append(project(center: center, distanceMeters: band.outerRadiusMeters, bearingDegrees: angle))
        }
        for step in stride(from: stepCount, through: 0, by: -1) {
            let progress = Double(step) / Double(stepCount)
            let angle = startAngle + ((endAngle - startAngle) * progress)
            ring.append(project(center: center, distanceMeters: band.innerRadiusMeters, bearingDegrees: angle))
        }

        if let first = ring.first {
            ring.append(first)
        }

        return Polygon([ring])
    }

    private static func project(
        center: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: CLLocationDirection
    ) -> LocationCoordinate2D {
        let bearingRadians = bearingDegrees * .pi / 180
        let latitudeRadians = center.latitude * .pi / 180
        let metersPerDegreeLatitude = 111_132.92 - (559.82 * cos(2 * latitudeRadians)) + (1.175 * cos(4 * latitudeRadians))
        let metersPerDegreeLongitude = max(1, 111_412.84 * cos(latitudeRadians) - (93.5 * cos(3 * latitudeRadians)))

        let latitudeOffset = (cos(bearingRadians) * distanceMeters) / metersPerDegreeLatitude
        let longitudeOffset = (sin(bearingRadians) * distanceMeters) / metersPerDegreeLongitude

        return LocationCoordinate2D(
            latitude: center.latitude + latitudeOffset,
            longitude: center.longitude + longitudeOffset
        )
    }
}
