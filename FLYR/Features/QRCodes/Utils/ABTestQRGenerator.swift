import Foundation
import UIKit
import CoreImage.CIFilterBuiltins

/// QR code generator for A/B test variants
/// Generates high-resolution PNG images for download/sharing
struct ABTestQRGenerator {
    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])
    
    /// Generate a 1024×1024 PNG QR code image from a URL
    /// - Parameter url: The URL string to encode in the QR code
    /// - Returns: PNG data, or nil if generation fails
    static func generatePNG(from url: String) -> Data? {
        let size = CGSize(width: 1024, height: 1024)
        
        guard let image = generateQRImage(from: url, size: size) else {
            print("❌ [AB Test QR] Failed to generate QR code image")
            return nil
        }
        
        // Convert to PNG data
        return image.pngData()
    }
    
    /// Generate QR code image with proper scaling and quiet space
    private static func generateQRImage(from string: String, size: CGSize) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        guard let outputImage = filter.outputImage else {
            print("❌ [AB Test QR] Failed to generate QR code image")
            return nil
        }
        
        // Calculate scale to fill the desired size with quiet space
        let scale = min(size.width, size.height) / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Create CGImage
        guard let cgImage = sharedContext.createCGImage(scaledImage, from: CGRect(origin: .zero, size: size)) else {
            print("❌ [AB Test QR] Failed to create CGImage from QR code")
            return nil
        }
        
        // Create UIImage with white background
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            // Fill with white background (quiet space)
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw QR code centered
            let qrSize = scaledImage.extent.size
            let x = (size.width - qrSize.width) / 2
            let y = (size.height - qrSize.height) / 2
            UIImage(cgImage: cgImage).draw(at: CGPoint(x: x, y: y))
        }
        
        return image
    }
    
    /// Present share sheet for QR code PNG
    /// - Parameters:
    ///   - url: The URL to generate QR code from
    ///   - viewController: The view controller to present from (optional, will find root if nil)
    static func shareQRCodePNG(url: String, from viewController: UIViewController? = nil) {
        guard let pngData = generatePNG(from: url),
              let image = UIImage(data: pngData) else {
            print("❌ [AB Test QR] Failed to generate PNG for sharing")
            return
        }
        
        // Create activity view controller
        let activityVC = UIActivityViewController(
            activityItems: [image, url],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            // You'll need to set the source view/bar button item when calling this
            popover.permittedArrowDirections = [.up, .down]
        }
        
        // Present from root view controller if not provided
        let presentingVC: UIViewController
        if let vc = viewController {
            presentingVC = vc
        } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController {
            presentingVC = rootViewController
        } else {
            print("❌ [AB Test QR] Could not find view controller to present from")
            return
        }
        
        // Find the topmost view controller
        var topVC = presentingVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        topVC.present(activityVC, animated: true)
    }
}

