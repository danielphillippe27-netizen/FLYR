import Foundation
import CoreImage.CIFilterBuiltins
import UIKit

/// Generates high-resolution PNG QR code images for export
struct QRPNGGenerator {
    // Reuse CIContext to avoid creating new context for each image
    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])
    
    /// Generate a 1024x1024 PNG QR code image
    /// - Parameters:
    ///   - url: The URL string to encode in the QR code
    ///   - qrId: Unique identifier for the QR code
    ///   - address: Optional address string for filename generation
    ///   - outputDirectory: Directory to save the PNG file
    /// - Returns: The filename of the generated PNG file
    /// - Throws: Error if generation or file writing fails
    static func generatePNG(
        url: String,
        qrId: UUID,
        address: String? = nil,
        outputDirectory: URL
    ) throws -> String {
        // Generate QR code image at 1024x1024
        let size = CGSize(width: 1024, height: 1024)
        
        guard let image = generateQRImage(from: url, size: size) else {
            throw QRExportError.pngGenerationFailed
        }
        
        // Generate filename
        let filename = generateFilename(qrId: qrId, address: address)
        
        // Ensure output directory exists
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Save PNG file
        let fileURL = outputDirectory.appendingPathComponent(filename)
        guard let pngData = image.pngData() else {
            throw QRExportError.pngDataConversionFailed
        }
        
        try pngData.write(to: fileURL)
        
        return filename
    }
    
    /// Generate QR code image with proper scaling and quiet space
    private static func generateQRImage(from string: String, size: CGSize) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        guard let outputImage = filter.outputImage else {
            print("❌ [QR Export] Failed to generate QR code image")
            return nil
        }
        
        // Calculate scale to fill the desired size with quiet space
        // QR codes need quiet space (white border) around them
        let scale = min(size.width, size.height) / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Use shared context to avoid creating new context for each image
        guard let cgImage = sharedContext.createCGImage(scaledImage, from: CGRect(origin: .zero, size: size)) else {
            print("❌ [QR Export] Failed to create CGImage from QR code")
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
    
    /// Generate filename from address or fallback to qr_<id>.png
    static func generateFilename(qrId: UUID, address: String?) -> String {
        if let address = address, !address.isEmpty {
            let kebabCase = addressToKebabCase(address)
            return "\(kebabCase).png"
        }
        return "qr_\(qrId.uuidString).png"
    }
    
    /// Convert address string to kebab-case filename
    private static func addressToKebabCase(_ address: String) -> String {
        // Remove special characters, convert to lowercase, replace spaces with hyphens
        let cleaned = address
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Replace multiple spaces with single space, then replace with hyphens
        let normalized = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
        
        // Limit length to avoid filesystem issues
        let maxLength = 100
        if normalized.count > maxLength {
            return String(normalized.prefix(maxLength))
        }
        
        return normalized.isEmpty ? "qr_\(UUID().uuidString)" : normalized
    }
}

/// QR Export specific errors
enum QRExportError: LocalizedError {
    case pngGenerationFailed
    case pngDataConversionFailed
    case csvGenerationFailed
    case zipCreationFailed
    case tempDirectoryCreationFailed
    case fileWriteFailed
    
    var errorDescription: String? {
        switch self {
        case .pngGenerationFailed:
            return "Failed to generate QR code PNG image"
        case .pngDataConversionFailed:
            return "Failed to convert QR code image to PNG data"
        case .csvGenerationFailed:
            return "Failed to generate CSV file"
        case .zipCreationFailed:
            return "Failed to create ZIP archive"
        case .tempDirectoryCreationFailed:
            return "Failed to create temporary directory"
        case .fileWriteFailed:
            return "Failed to write file"
        }
    }
}

