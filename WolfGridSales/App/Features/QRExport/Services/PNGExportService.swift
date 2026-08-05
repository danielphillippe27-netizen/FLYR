import Foundation
import UIKit

/// Generates 1024×1024 PNG files for each QR code address
struct PNGExportService {
    
    /// Generate PNG files for all addresses
    /// - Parameters:
    ///   - addresses: Array of addresses with QR code data
    ///   - outputDirectory: Directory where PNG files should be saved (will create qr/ subdirectory)
    ///   - useTransparentBackground: Whether to use transparent background (default: false for white)
    /// - Returns: Dictionary mapping address IDs to filenames
    /// - Throws: ExportError if generation fails
    static func generatePNGs(
        addresses: [QRCodeAddress],
        outputDirectory: URL,
        useTransparentBackground: Bool = false
    ) throws -> [UUID: String] {
        guard !addresses.isEmpty else {
            throw ExportError.invalidAddresses
        }
        
        // Create qr/ subdirectory
        let qrDirectory = outputDirectory.appendingPathComponent("qr", isDirectory: true)
        try FileManager.default.createDirectory(
            at: qrDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        var filenames: [UUID: String] = [:]
        var lastError: Error?
        
        // Generate PNG for each address
        for address in addresses {
            autoreleasepool {
                do {
                    let filename = try generatePNG(
                        for: address,
                        outputDirectory: qrDirectory,
                        useTransparentBackground: useTransparentBackground
                    )
                    filenames[address.id] = filename
                } catch {
                    lastError = error
                    print("⚠️ [PNG Export] Failed to generate PNG for address \(address.id): \(error)")
                }
            }
        }
        
        // Throw error if any occurred
        if let error = lastError {
            throw ExportError.pngGenerationFailed(error.localizedDescription)
        }
        
        return filenames
    }
    
    /// Generate a single PNG file for an address
    /// - Parameters:
    ///   - address: Address to generate QR code for
    ///   - outputDirectory: Directory where PNG should be saved
    ///   - useTransparentBackground: Whether to use transparent background
    /// - Returns: Filename of the generated PNG
    /// - Throws: ExportError if generation fails
    private static func generatePNG(
        for address: QRCodeAddress,
        outputDirectory: URL,
        useTransparentBackground: Bool
    ) throws -> String {
        // Generate QR code image at 1024×1024
        let size = CGSize(width: 1024, height: 1024)
        
        guard let qrImage = QRCodeGenerator.generate(from: address.webURL, size: size) else {
            throw ExportError.pngGenerationFailed("Failed to generate QR code image")
        }
        
        // Create final image with background
        let finalImage: UIImage
        if useTransparentBackground {
            finalImage = qrImage
        } else {
            // Create image with white background
            let renderer = UIGraphicsImageRenderer(size: size)
            finalImage = renderer.image { context in
                // Fill white background
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                
                // Draw QR code
                qrImage.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        
        // Generate filename from address
        let slug = StringSlugifier.slugify(address.formatted)
        let filename = "\(slug).png"
        let fileURL = outputDirectory.appendingPathComponent(filename)
        
        // Save PNG file
        guard let pngData = finalImage.pngData() else {
            throw ExportError.pngGenerationFailed("Failed to convert image to PNG data")
        }
        
        try pngData.write(to: fileURL)
        
        return filename
    }
}

