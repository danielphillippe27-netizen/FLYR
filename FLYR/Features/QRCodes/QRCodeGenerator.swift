import Foundation
import CoreImage.CIFilterBuiltins
import UIKit

/// Utility for generating QR code images from strings
public struct QRCodeGenerator {
    
    /// Generate a QR code image from a string with print quality (600x600)
    /// - Parameters:
    ///   - string: The string to encode in the QR code
    ///   - size: The desired size of the output image (default: 600x600 for print quality)
    /// - Returns: A UIImage of the QR code, or nil if generation fails
    public static func generate(from string: String, size: CGSize = CGSize(width: 600, height: 600)) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        
        // Set error correction level for better quality
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        guard let outputImage = filter.outputImage else {
            print("❌ [QR] Failed to generate QR code image")
            return nil
        }
        
        // Calculate scale factor to reach desired size
        // CIFilter outputs at ~33x33, so we need to scale appropriately
        let scale = size.width / outputImage.extent.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)
        
        // Convert to UIImage with high quality
        let context = CIContext(options: [
            .useSoftwareRenderer: false, // Use hardware acceleration
            .workingColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            print("❌ [QR] Failed to create CGImage from QR code")
            return nil
        }
        
        // Create UIImage from CGImage
        return UIImage(cgImage: cgImage)
    }
    
    /// Generate QR code image data for storage
    /// - Parameters:
    ///   - string: The string to encode
    ///   - size: The desired size (default: 600x600)
    /// - Returns: PNG data representation of the QR code
    public static func generateData(from string: String, size: CGSize = CGSize(width: 600, height: 600)) -> Data? {
        guard let image = generate(from: string, size: size) else {
            return nil
        }
        return image.pngData()
    }
    
    /// Generate QR code and return as Base64 encoded string
    /// - Parameters:
    ///   - string: The string to encode
    ///   - size: The desired size (default: 600x600)
    /// - Returns: Base64 encoded PNG string, or nil if generation fails
    public static func generateBase64(from string: String, size: CGSize = CGSize(width: 600, height: 600)) -> String? {
        guard let image = generate(from: string, size: size),
              let pngData = image.pngData() else {
            return nil
        }
        return pngData.base64EncodedString()
    }
    
    /// Generate QR code with custom error correction level
    /// - Parameters:
    ///   - string: The string to encode
    ///   - size: The desired size
    ///   - errorCorrectionLevel: Error correction level (L, M, Q, H) - default is H (highest)
    /// - Returns: A UIImage of the QR code, or nil if generation fails
    public static func generate(
        from string: String,
        size: CGSize = CGSize(width: 600, height: 600),
        errorCorrectionLevel: String = "H"
    ) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(errorCorrectionLevel, forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else {
            print("❌ [QR] Failed to generate QR code image")
            return nil
        }
        
        let scale = size.width / outputImage.extent.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)
        
        let context = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            print("❌ [QR] Failed to create CGImage from QR code")
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}



