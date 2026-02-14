import SwiftUI
import UIKit

// MARK: - Share Card Generator

enum ShareCardGenerator {

    private static let canvasWidth: CGFloat = 1080
    private static let canvasHeight: CGFloat = 1920

    /// Generate a PNG for the share card. Transparent when isTransparent is true.
    static func generateTransparentPNG(stats: ShareCardSessionStats, isTransparent: Bool = true) -> UIImage? {
        let view = ShareCardView(stats: stats, isTransparent: isTransparent)
            .frame(width: Self.canvasWidth, height: Self.canvasHeight)
            .background(Color.clear)

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        if renderer.scale < 2 { renderer.scale = 2 }
        renderer.isOpaque = !isTransparent
        return renderer.uiImage
    }

    /// Share to Instagram Stories (pasteboard + URL scheme). Returns true if IG was opened, false to use fallback.
    static func shareToInstagramStories(_ image: UIImage) -> Bool {
        guard let imageData = image.pngData() else { return false }
        let pasteboard = UIPasteboard.general
        pasteboard.setData(imageData, forPasteboardType: "com.instagram.sharedSticker.backgroundImage")
        guard let url = URL(string: "instagram-stories://share"),
              UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    /// Generic share sheet (fallback when IG not installed or for "Share…").
    static func shareImage(_ image: UIImage, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(
            activityItems: [image],
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
