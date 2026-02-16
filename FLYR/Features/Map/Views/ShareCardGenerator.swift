import SwiftUI
import UIKit

// MARK: - Share Card Generator
/// Helper utilities for sharing session summary cards (used by EndSessionSummaryView).
enum ShareCardGenerator {

    /// Share to Instagram Stories as a sticker (preserves transparency). Returns true if IG was opened, false to use fallback.
    @MainActor
    static func shareToInstagramStories(_ image: UIImage) -> Bool {
        // Check if Instagram is installed
        guard let url = URL(string: "instagram-stories://share"),
              UIApplication.shared.canOpenURL(url) else {
            print("❌ Instagram not installed or URL scheme not supported")
            return false
        }
        
        // Clear pasteboard and set image data
        let pasteboard = UIPasteboard.general
        pasteboard.items = []
        
        guard let imageData = image.pngData() else {
            print("❌ Failed to convert image to PNG")
            return false
        }
        
        // Set the sticker image data
        pasteboard.setData(imageData, forPasteboardType: "com.instagram.sharedSticker.stickerImage")
        
        // Open Instagram
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                print("❌ Failed to open Instagram")
            }
        }
        return true
    }

    /// Share to Instagram Stories as background (fills transparent areas with black).
    @MainActor
    static func shareToInstagramStoriesAsBackground(_ image: UIImage) -> Bool {
        // Check if Instagram is installed
        guard let url = URL(string: "instagram-stories://share"),
              UIApplication.shared.canOpenURL(url) else {
            print("❌ Instagram not installed or URL scheme not supported")
            return false
        }
        
        // Clear pasteboard and set image data
        let pasteboard = UIPasteboard.general
        pasteboard.items = []
        
        guard let imageData = image.pngData() else {
            print("❌ Failed to convert image to PNG")
            return false
        }
        
        // Set the background image data
        pasteboard.setData(imageData, forPasteboardType: "com.instagram.sharedSticker.backgroundImage")
        
        // Open Instagram
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
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Fill background
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        // Draw image on top
        image.draw(in: CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext()
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
    fileprivate static func removePhotoSaveHandler(_ handler: PhotoSaveHandler) {
        photoSaveHandlers.removeAll { $0 === handler }
    }

    /// Generates both PNG variants (doors/distance/time and doors/conversations/distance) for the given session data.
    @MainActor
    static func generateShareImages(data: SessionSummaryData) -> [UIImage] {
        let size = CGSize(width: 1080, height: 1920)
        var result: [UIImage] = []
        for metrics in [ShareCardMetrics.doorsDistanceTime, .doorsConvoTime] {
            let card = SessionShareCardView(data: data, forExport: true, metrics: metrics)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            renderer.isOpaque = false
            if let uiImage = renderer.uiImage, let pngData = uiImage.pngData(), let img = UIImage(data: pngData) {
                result.append(img)
            }
        }
        return result
    }

    /// Root view controller for presenting share sheet from SwiftUI.
    static func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return nil }
        var vc = root
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }
}
