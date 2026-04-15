import SwiftUI
import UIKit
import CoreLocation

// MARK: - Share Card Generator
/// Helper utilities for sharing session summary cards (used by EndSessionSummaryView).
enum ShareCardGenerator {

    /// Shown when no UIKit view controller is available to present `UIActivityViewController` (rare).
    static let shareSheetUnavailableUserMessage = "Couldn't open the share sheet. Try again in a moment."
    private static let instagramStoriesScheme = "instagram-stories://share"
    private static let instagramStoriesPasteboardExpiration: TimeInterval = 60 * 5

    private static var metaAppID: String? {
        Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String
    }
    private static let homesMapSnapshotCache = NSCache<NSString, UIImage>()

    /// Share to Instagram Stories as a sticker (preserves transparency). Returns true if IG was opened, false to use fallback.
    @MainActor
    static func shareToInstagramStories(_ image: UIImage) -> Bool {
        guard let appID = metaAppID,
              let url = URL(string: "\(instagramStoriesScheme)?source_application=\(appID)"),
              UIApplication.shared.canOpenURL(url) else {
            print("❌ Instagram not installed or URL scheme not supported")
            return false
        }

        guard let imageData = image.pngData() else {
            print("❌ Failed to convert image to PNG")
            return false
        }

        let pasteboardItems: [String: Any] = [
            "com.instagram.sharedSticker.stickerImage": imageData,
            "com.instagram.sharedSticker.appID": appID
        ]

        UIPasteboard.general.setItems(
            [pasteboardItems],
            options: [.expirationDate: Date().addingTimeInterval(instagramStoriesPasteboardExpiration)]
        )

        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                print("❌ Failed to open Instagram")
            }
        }
        return true
    }

    /// Share to Instagram Stories as background (fills transparent areas with black).
    @MainActor
    static func shareToInstagramStoriesAsBackground(_ image: UIImage, contentURL: URL? = nil) -> Bool {
        guard let appID = metaAppID,
              let url = URL(string: "\(instagramStoriesScheme)?source_application=\(appID)"),
              UIApplication.shared.canOpenURL(url) else {
            print("❌ Instagram not installed or URL scheme not supported")
            return false
        }

        let flattenedImage = addBackground(to: image, color: .black) ?? image

        guard let imageData = flattenedImage.pngData() else {
            print("❌ Failed to convert image to PNG")
            return false
        }

        var pasteboardItems: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": imageData,
            "com.instagram.sharedSticker.appID": appID
        ]
        if let contentURL {
            pasteboardItems["com.instagram.sharedSticker.contentURL"] = contentURL.absoluteString
        }

        UIPasteboard.general.setItems(
            [pasteboardItems],
            options: [.expirationDate: Date().addingTimeInterval(instagramStoriesPasteboardExpiration)]
        )

        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                print("❌ Failed to open Instagram")
            }
        }
        return true
    }

    /// Composites transparent image onto a solid color background.
    static func addBackground(to image: UIImage, color: UIColor) -> UIImage? {
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, true, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Fill background
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        // Draw image on top
        image.draw(in: CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Presents the system share sheet from the topmost view controller (works from nested SwiftUI navigation; avoids hosting `UIActivityViewController` inside a SwiftUI `.sheet`).
    /// - Returns: `false` if there was nothing to share or no presenter was found (caller may show `shareSheetUnavailableUserMessage`).
    @MainActor
    @discardableResult
    static func presentActivityShare(activityItems: [Any]) -> Bool {
        guard !activityItems.isEmpty, let presenter = rootViewController() else { return false }
        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
        return true
    }

    /// Generic share sheet (fallback when IG not installed or for "Share…").
    static func shareImage(_ image: UIImage, from viewController: UIViewController) {
        shareImages([image], from: viewController)
    }

    /// Share multiple images (e.g. both PNG variants) via the system share sheet.
    static func shareImages(_ images: [UIImage], from viewController: UIViewController) {
        guard !images.isEmpty else { return }
        let activityVC = UIActivityViewController(
            activityItems: images,
            applicationActivities: nil
        )
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
        }
        viewController.present(activityVC, animated: true)
    }

    private static var photoSaveHandlers: [PhotoSaveHandler] = []

    /// Save to Photos with success/failure callback (for toast).
    static func saveToPhotos(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        let handler = PhotoSaveHandler(completion: completion)
        Self.photoSaveHandlers.append(handler)
        UIImageWriteToSavedPhotosAlbum(image, handler, #selector(PhotoSaveHandler.didFinish(_:didFinishSavingWithError:contextInfo:)), nil)
    }
}

private final class PhotoSaveHandler: NSObject {
    let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }
    @objc func didFinish(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        DispatchQueue.main.async {
            self.completion(error == nil)
            ShareCardGenerator.removePhotoSaveHandler(self)
        }
    }
}

extension ShareCardGenerator {
    enum HomesMapTheme: String {
        case light
        case dark

        var stylePath: String {
            switch self {
            case .light:
                return "fliper27/cml6z0dhg002301qo9xxc08k4"
            case .dark:
                return "fliper27/cml6zc5pq002801qo4lh13o19"
            }
        }
    }

    fileprivate static func removePhotoSaveHandler(_ handler: PhotoSaveHandler) {
        photoSaveHandlers.removeAll { $0 === handler }
    }

    @MainActor
    static func renderImage<Content: View>(
        content: Content,
        size: CGSize = CGSize(width: 1080, height: 1920)
    ) -> UIImage? {
        let card = content.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        renderer.isOpaque = false
        guard let uiImage = renderer.uiImage,
              let pngData = uiImage.pngData() else { return nil }
        return UIImage(data: pngData)
    }

    /// Generates both PNG variants (route card + metric cards) for the given session data.
    /// - Parameters:
    ///   - showVectorOverlay: When nil, uses `!data.isDemoSession`. Set explicitly when using a live campaign capture (usually `false` so route/homes aren’t drawn twice).
    @MainActor
    static func generateShareImages(
        data: SessionSummaryData,
        homesMapSnapshot: UIImage? = nil,
        showVectorOverlay: Bool? = nil
    ) -> [UIImage] {
        let vectors = showVectorOverlay ?? (!data.isDemoSession)
        var result: [UIImage] = []
        if data.includesHomesRouteShareCard {
            if let img = renderImage(
                content: SessionHomesShareCardView(
                    data: data,
                    forExport: true,
                    backgroundSnapshot: homesMapSnapshot,
                    showVectorOverlay: vectors
                )
            ) {
                result.append(img)
            }
        }
        for metrics in [ShareCardMetrics.doorsDistanceTime, .doorsConvoTime] {
            if let img = renderImage(
                content: SessionShareCardView(data: data, forExport: true, metrics: metrics)
            ) {
                result.append(img)
            }
        }
        return result
    }

    /// Async variant: prefers a **live campaign map capture** when provided; otherwise loads Mapbox static imagery.
    static func generateShareImages(
        data: SessionSummaryData,
        homesMapTheme: HomesMapTheme,
        campaignMapSnapshot: UIImage? = nil
    ) async -> [UIImage] {
        let exportSize = CGSize(width: 1080, height: 1920)
        let bg: UIImage?
        let vectors: Bool
        if let campaign = campaignMapSnapshot {
            bg = campaign
            vectors = false
        } else {
            bg = await loadHomesMapSnapshot(for: data, theme: homesMapTheme, size: exportSize)
            vectors = !data.isDemoSession
        }
        return await MainActor.run {
            generateShareImages(data: data, homesMapSnapshot: bg, showVectorOverlay: vectors)
        }
    }

    static func preferredHomesMapSnapshot(
        for data: SessionSummaryData,
        theme: HomesMapTheme,
        size: CGSize
    ) async -> UIImage? {
        return await loadHomesMapSnapshot(for: data, theme: theme, size: size)
    }

    static func loadHomesMapSnapshot(
        for data: SessionSummaryData,
        theme: HomesMapTheme,
        size: CGSize
    ) async -> UIImage? {
        guard data.includesHomesRouteShareCard else { return nil }
        let coordinates = preferredSnapshotCoordinates(for: data)
        guard !coordinates.isEmpty else { return nil }

        let cacheKey = homesMapSnapshotCacheKey(for: coordinates, theme: theme, size: size)
        if let cached = homesMapSnapshotCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        guard let accessToken = mapboxAccessToken,
              let url = homesMapSnapshotURL(for: coordinates, theme: theme, size: size, accessToken: accessToken) else {
            return nil
        }

        do {
            let (imageData, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = UIImage(data: imageData) else {
                return nil
            }
            homesMapSnapshotCache.setObject(image, forKey: cacheKey as NSString)
            return image
        } catch {
            print("⚠️ [ShareCardGenerator] Failed to load homes map snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    private static var mapboxAccessToken: String? {
        MapboxManager.shared.accessToken.isEmpty ? nil : MapboxManager.shared.accessToken
    }

    private static func preferredSnapshotCoordinates(for data: SessionSummaryData) -> [CLLocationCoordinate2D] {
        let segments = data.displayRouteSegments.flatMap { $0 }.filter { CLLocationCoordinate2DIsValid($0) }
        let homes = data.completedHomeCoordinates.filter { CLLocationCoordinate2DIsValid($0) }
        if !segments.isEmpty && !homes.isEmpty { return segments + homes }
        if !segments.isEmpty { return segments }
        if !homes.isEmpty { return homes }
        let route = data.pathCoordinates.filter { CLLocationCoordinate2DIsValid($0) }
        if route.count >= 2 { return route }
        return homes
    }

    private static func homesMapSnapshotCacheKey(
        for coordinates: [CLLocationCoordinate2D],
        theme: HomesMapTheme,
        size: CGSize
    ) -> String {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        return "\(theme.rawValue)-\(Int(size.width))x\(Int(size.height))-\(String(format: "%.5f", minLat))-\(String(format: "%.5f", maxLat))-\(String(format: "%.5f", minLon))-\(String(format: "%.5f", maxLon))-\(coordinates.count)"
    }

    private static func homesMapSnapshotURL(
        for coordinates: [CLLocationCoordinate2D],
        theme: HomesMapTheme,
        size: CGSize,
        accessToken: String
    ) -> URL? {
        guard let viewport = snapshotViewport(for: coordinates, size: size) else { return nil }
        let width = max(Int(size.width), 320)
        let height = max(Int(size.height), 568)
        let urlString = String(
            format: "https://api.mapbox.com/styles/v1/%@/static/%.6f,%.6f,%.2f,0,42/%dx%d@2x?logo=false&attribution=false&access_token=%@",
            theme.stylePath,
            viewport.center.longitude,
            viewport.center.latitude,
            viewport.zoom,
            width,
            height,
            accessToken
        )
        return URL(string: urlString)
    }

    private static func snapshotViewport(
        for coordinates: [CLLocationCoordinate2D],
        size: CGSize
    ) -> (center: CLLocationCoordinate2D, zoom: Double)? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)

        let mapWidth = max(Double(size.width) * 2 * 0.82, 64)
        let mapHeight = max(Double(size.height) * 2 * 0.82, 64)
        let lngDiff = max(maxLon - minLon, 0.00018)
        let lngFraction = min(max(lngDiff / 360.0, 0.000001), 1)
        let latFraction = min(max((mercatorY(maxLat) - mercatorY(minLat)) / .pi, 0.000001), 1)

        let lngZoom = log2(mapWidth / 512.0 / lngFraction)
        let latZoom = log2(mapHeight / 512.0 / latFraction)
        let zoom = min(max(min(lngZoom, latZoom) - 0.45, 3.2), 18.2)
        return (center, zoom)
    }

    private static func mercatorY(_ latitude: Double) -> Double {
        let sinValue = sin(latitude * .pi / 180.0)
        let radX2 = log((1 + sinValue) / (1 - sinValue)) / 2
        return max(min(radX2, .pi), -.pi) / 2
    }

    /// Root view controller for presenting share sheet from SwiftUI.
    /// Uses the foreground window scene (not `connectedScenes.first`, which is undefined order) and falls back if no key window is set yet.
    static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let orderedScenes: [UIWindowScene] = {
            let active = scenes.filter { $0.activationState == .foregroundActive }
            if !active.isEmpty { return active }
            let inactive = scenes.filter { $0.activationState == .foregroundInactive }
            if !inactive.isEmpty { return inactive }
            return scenes
        }()

        func windowForPresentation(in scene: UIWindowScene) -> UIWindow? {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) { return key }
            return scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 && $0.rootViewController != nil })
                ?? scene.windows.first
        }

        for scene in orderedScenes {
            guard let window = windowForPresentation(in: scene),
                  let root = window.rootViewController else { continue }
            return root.flyr_topPresenterForModal
        }
        return nil
    }
}

private extension UIViewController {
    /// Topmost controller that should own a new modal (share sheet, alerts, etc.).
    var flyr_topPresenterForModal: UIViewController {
        if let presented = presentedViewController {
            return presented.flyr_topPresenterForModal
        }
        if let split = self as? UISplitViewController,
           let last = split.viewControllers.last {
            return last.flyr_topPresenterForModal
        }
        if let nav = self as? UINavigationController {
            return (nav.visibleViewController ?? nav).flyr_topPresenterForModal
        }
        if let tab = self as? UITabBarController {
            return (tab.selectedViewController ?? tab).flyr_topPresenterForModal
        }
        if let visibleChild = children.reversed().first(where: {
            $0.viewIfLoaded?.window != nil && !$0.isBeingDismissed
        }) {
            return visibleChild.flyr_topPresenterForModal
        }
        return self
    }
}
