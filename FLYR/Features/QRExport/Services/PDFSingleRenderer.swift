import Foundation
import UIKit
import PDFKit

/// Renders one QR code per page for print shop use
struct PDFSingleRenderer {
    
    /// Generate a PDF with one QR code per page
    /// - Parameters:
    ///   - addresses: Array of addresses with QR code data
    ///   - batchName: Name for the batch
    ///   - outputURL: URL where the PDF should be saved
    /// - Returns: URL of the created PDF file
    /// - Throws: ExportError if generation fails
    static func generatePDF(
        addresses: [QRCodeAddress],
        batchName: String,
        outputURL: URL
    ) throws -> URL {
        guard !addresses.isEmpty else {
            throw ExportError.invalidAddresses
        }
        
        // Page size: A4 or US Letter based on locale
        let isMetric = Locale.current.usesMetricSystem
        let pageWidth: CGFloat = isMetric ? 595.0 : 612.0  // A4: 595×842, US Letter: 612×792
        let pageHeight: CGFloat = isMetric ? 842.0 : 792.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        // QR code size: 500px (scales to 600px if needed)
        let qrSize: CGFloat = 500.0
        
        // Top padding: 100pt
        let topPadding: CGFloat = 100.0
        
        // PDF metadata
        let pdfMetaData = [
            kCGPDFContextCreator: "FLYR",
            kCGPDFContextAuthor: "FLYR App",
            kCGPDFContextTitle: batchName
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        // Sanitize filename
        let sanitizedBatchName = StringSlugifier.slugify(batchName)
        let pdfURL = outputURL.appendingPathComponent("\(sanitizedBatchName)_single.pdf")
        
        // Remove existing PDF if it exists
        if FileManager.default.fileExists(atPath: pdfURL.path) {
            try? FileManager.default.removeItem(at: pdfURL)
        }
        
        let pdfData = renderer.pdfData { context in
            for (index, address) in addresses.enumerated() {
                if index > 0 {
                    context.beginPage()
                }
                
                // Center QR code horizontally
                let qrX = (pageWidth - qrSize) / 2.0
                let qrY = topPadding
                
                // Generate QR code image
                if let qrImage = generateQRCodeImage(from: address.webURL, size: CGSize(width: qrSize, height: qrSize)) {
                    // Draw QR code
                    qrImage.draw(in: CGRect(x: qrX, y: qrY, width: qrSize, height: qrSize))
                    
                    // Draw address label below QR code, centered
                    let addressY = qrY + qrSize + 20.0
                    let addressHeight: CGFloat = 40.0
                    let addressMargin: CGFloat = 40.0
                    let addressRect = CGRect(x: addressMargin, y: addressY, width: pageWidth - (addressMargin * 2), height: addressHeight)
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    paragraphStyle.lineBreakMode = .byWordWrapping
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    address.formatted.draw(in: addressRect, withAttributes: attributes)
                }
            }
        }
        
        try pdfData.write(to: pdfURL)
        return pdfURL
    }
    
    private static let margin: CGFloat = 40.0
    
    /// Generate QR code image from URL string
    private static func generateQRCodeImage(from urlString: String, size: CGSize) -> UIImage? {
        return QRCodeGenerator.generate(from: urlString, size: size)
    }
}

