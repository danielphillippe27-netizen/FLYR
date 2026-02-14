import UIKit

/// Provides the red stick-man location marker image for map annotations.
/// Image is shown upside down (pointing down for location) at 1/4 scale.
enum LocationMarkerImage {
    static let imageName = "flyr-location-marker"

    /// Marker image: upside down, 1/4 size (small so it stays tied to the map point).
    static var markerImage: UIImage? {
        guard let source = UIImage(named: "RedStickman") else { return nil }
        return scaledForMarker(source)
    }

    /// Scale to 1/4 of original marker size; no flip so the figure points down (location pin style).
    private static func scaledForMarker(_ image: UIImage) -> UIImage? {
        let targetHeight: CGFloat = 10  // 1/4 of previous 40
        let scale = targetHeight / image.size.height
        let targetSize = CGSize(width: image.size.width * scale, height: targetHeight)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
