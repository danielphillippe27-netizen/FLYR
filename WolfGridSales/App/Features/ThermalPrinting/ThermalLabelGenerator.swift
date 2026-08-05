import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import CoreGraphics

/// Generates thermal-ready QR label PNG images
public struct ThermalLabelGenerator {
    
    /// Generate a thermal-ready label PNG
    /// - Parameters:
    ///   - url: The URL string to encode in the QR code
    ///   - address: Optional address text to display on label
    ///   - campaignName: Optional campaign name to display on label
    ///   - size: Label size (2×2 or 3×3 inches)
    /// - Returns: URL to the generated PNG file in temporary directory
    /// - Throws: Error if generation fails
    public static func generate(
        url: String,
        address: String?,
        campaignName: String?,
        size: ThermalLabelSize
    ) throws -> URL {
        let canvasSize = size.pixelSize
        
        // Generate QR code before rendering (outside the non-throwing closure)
        guard let qrImage = generateQRCode(from: url, size: size) else {
            throw ThermalLabelError.qrGenerationFailed
        }
        
        guard let cgQRImage = qrImage.cgImage else {
            throw ThermalLabelError.qrGenerationFailed
        }
        
        // Create image context
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // Fill white background
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: canvasSize))
            
            // Calculate layout
            let qrHeight = canvasSize.height * 0.7  // QR takes 70% of height
            let textAreaHeight = canvasSize.height * 0.3  // Text takes 30% of height
            let padding: CGFloat = 20
            
            // Draw QR code (centered horizontally, at top)
            let qrWidth = qrHeight  // Square QR code
            let qrX = (canvasSize.width - qrWidth) / 2
            let qrY = padding
            let qrRect = CGRect(x: qrX, y: qrY, width: qrWidth, height: qrHeight)
            
            // Draw QR code
            cgContext.draw(cgQRImage, in: qrRect)
            
            // Draw text in remaining area
            let textY = qrY + qrHeight + padding
            let textRect = CGRect(
                x: padding,
                y: textY,
                width: canvasSize.width - (padding * 2),
                height: textAreaHeight - (padding * 2)
            )
            
            drawText(
                in: textRect,
                context: cgContext,
                address: address,
                campaignName: campaignName,
                labelSize: size
            )
        }
        
        // Save to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "thermal_label_\(UUID().uuidString).png"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        guard let pngData = image.pngData() else {
            throw ThermalLabelError.pngExportFailed
        }
        
        try pngData.write(to: fileURL)
        
        return fileURL
    }
    
    /// Generate pure black QR code image
    private static func generateQRCode(from string: String, size: ThermalLabelSize) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")  // High error correction
        
        guard let outputImage = filter.outputImage else {
            return nil
        }
        
        // Calculate QR size (70% of canvas height, minus padding)
        let canvasSize = size.pixelSize
        let qrSize = canvasSize.height * 0.7 - 40  // 40px padding total
        
        // Scale up the QR code for high resolution
        // QR codes are typically small, so we need significant scaling
        let scale = qrSize / outputImage.extent.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)
        
        // Convert to pure black and white
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        // Create bitmap context for pure black/white conversion
        let width = Int(scaledImage.extent.width)
        let height = Int(scaledImage.extent.height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return UIImage(cgImage: cgImage)
        }
        
        // Draw and threshold to pure black/white
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Get pixel data and threshold
        guard let data = bitmapContext.data else {
            return UIImage(cgImage: cgImage)
        }
        
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height) {
            // Threshold: anything below 128 becomes 0 (black), else 255 (white)
            pixels[i] = pixels[i] < 128 ? 0 : 255
        }
        
        guard let finalCGImage = bitmapContext.makeImage() else {
            return UIImage(cgImage: cgImage)
        }
        
        return UIImage(cgImage: finalCGImage)
    }
    
    /// Draw text on the label
    private static func drawText(
        in rect: CGRect,
        context: CGContext,
        address: String?,
        campaignName: String?,
        labelSize: ThermalLabelSize
    ) {
        // Calculate font sizes based on label size
        let baseFontSize: CGFloat = labelSize == .size2x2 ? 14 : 20
        let smallFontSize: CGFloat = labelSize == .size2x2 ? 10 : 14
        
        let addressFont = UIFont.systemFont(ofSize: baseFontSize, weight: .medium)
        let campaignFont = UIFont.systemFont(ofSize: smallFontSize, weight: .regular)
        let scanMeFont = UIFont.systemFont(ofSize: smallFontSize, weight: .medium)
        
        var currentY: CGFloat = rect.minY
        let lineSpacing: CGFloat = labelSize == .size2x2 ? 4 : 6
        
        // Set text drawing attributes
        context.setFillColor(UIColor.black.cgColor)
        context.setTextDrawingMode(.fill)
        
        // Draw address if provided
        if let address = address, !address.isEmpty {
            let addressAttributes: [NSAttributedString.Key: Any] = [
                .font: addressFont,
                .foregroundColor: UIColor.black
            ]
            let addressText = NSAttributedString(string: address, attributes: addressAttributes)
            let addressSize = addressText.boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            
            // Center text horizontally
            let addressX = rect.minX + (rect.width - addressSize.width) / 2
            let addressRect = CGRect(x: addressX, y: currentY, width: addressSize.width, height: addressSize.height)
            addressText.draw(in: addressRect)
            currentY += addressSize.height + lineSpacing
        }
        
        // Draw campaign name if provided
        if let campaignName = campaignName, !campaignName.isEmpty {
            let campaignAttributes: [NSAttributedString.Key: Any] = [
                .font: campaignFont,
                .foregroundColor: UIColor.black
            ]
            let campaignText = NSAttributedString(string: campaignName, attributes: campaignAttributes)
            let campaignSize = campaignText.boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).size
            
            // Center text horizontally
            let campaignX = rect.minX + (rect.width - campaignSize.width) / 2
            let campaignRect = CGRect(x: campaignX, y: currentY, width: campaignSize.width, height: campaignSize.height)
            campaignText.draw(in: campaignRect)
            currentY += campaignSize.height + lineSpacing
        }
        
        // Draw "Scan Me" text
        let scanMeAttributes: [NSAttributedString.Key: Any] = [
            .font: scanMeFont,
            .foregroundColor: UIColor.black
        ]
        let scanMeText = NSAttributedString(string: "Scan Me", attributes: scanMeAttributes)
        let scanMeSize = scanMeText.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size
        
        // Center text horizontally
        let scanMeX = rect.minX + (rect.width - scanMeSize.width) / 2
        let scanMeRect = CGRect(x: scanMeX, y: currentY, width: scanMeSize.width, height: scanMeSize.height)
        scanMeText.draw(in: scanMeRect)
    }
}

/// Errors that can occur during label generation
public enum ThermalLabelError: LocalizedError {
    case qrGenerationFailed
    case pngExportFailed
    
    public var errorDescription: String? {
        switch self {
        case .qrGenerationFailed:
            return "Failed to generate QR code"
        case .pngExportFailed:
            return "Failed to export PNG image"
        }
    }
}

