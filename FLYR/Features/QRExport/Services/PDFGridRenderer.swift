import Foundation
import UIKit
import PDFKit

/// Renders QR codes in a grid layout (2×3 or 3×3) for print/home use
struct PDFGridRenderer {
    
    /// Generate a PDF with QR codes in a grid layout
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
        
        // Auto-select grid layout: 2×3 (6 per page) or 3×3 (9 per page)
        // Use 3×3 for larger batches, 2×3 for smaller ones
        let use3x3 = addresses.count > 12
        let qrCodesPerRow = use3x3 ? 3 : 2
        let qrCodesPerColumn = use3x3 ? 3 : 3
        let qrCodesPerPage = qrCodesPerRow * qrCodesPerColumn
        
        // Page size: A4 or US Letter based on locale
        let isMetric = Locale.current.usesMetricSystem
        let pageWidth: CGFloat = isMetric ? 595.0 : 612.0  // A4: 595×842, US Letter: 612×792
        let pageHeight: CGFloat = isMetric ? 842.0 : 792.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        // Margins: 24pt all sides
        let margin: CGFloat = 24.0
        
        // QR code size: 450×450px
        let qrSize: CGFloat = 450.0
        
        // Calculate available space
        let availableWidth = pageWidth - (margin * 2)
        let availableHeight = pageHeight - (margin * 2)
        
        // Calculate spacing between QR codes
        let horizontalSpacing = (availableWidth - (CGFloat(qrCodesPerRow) * qrSize)) / CGFloat(max(1, qrCodesPerRow - 1))
        let verticalSpacing = (availableHeight - (CGFloat(qrCodesPerColumn) * qrSize) - (CGFloat(qrCodesPerColumn) * 30.0)) / CGFloat(max(1, qrCodesPerColumn - 1))
        
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
        let pdfURL = outputURL.appendingPathComponent("\(sanitizedBatchName)_grid.pdf")
        
        // Remove existing PDF if it exists
        if FileManager.default.fileExists(atPath: pdfURL.path) {
            try? FileManager.default.removeItem(at: pdfURL)
        }
        
        let pdfData = renderer.pdfData { context in
            var addressIndex = 0
            var hasStartedFirstPage = false
            
            while addressIndex < addresses.count {
                // Start new page if needed
                if addressIndex % qrCodesPerPage == 0 {
                    if hasStartedFirstPage {
                        context.beginPage()
                    } else {
                        hasStartedFirstPage = true
                    }
                }
                
                let positionInPage = addressIndex % qrCodesPerPage
                let row = positionInPage / qrCodesPerRow
                let col = positionInPage % qrCodesPerRow
                
                // Calculate position
                let x = margin + CGFloat(col) * (qrSize + horizontalSpacing)
                let y = margin + CGFloat(row) * (qrSize + verticalSpacing + 30.0) // 30pt for label
                
                let address = addresses[addressIndex]
                
                // Generate QR code image
                if let qrImage = generateQRCodeImage(from: address.webURL, size: CGSize(width: qrSize, height: qrSize)) {
                    // Draw QR code
                    qrImage.draw(in: CGRect(x: x, y: y, width: qrSize, height: qrSize))
                    
                    // Draw address label below QR code
                    let addressRect = CGRect(x: x, y: y + qrSize + 5, width: qrSize, height: 25)
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    paragraphStyle.lineBreakMode = .byTruncatingTail
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    address.formatted.draw(in: addressRect, withAttributes: attributes)
                }
                
                addressIndex += 1
            }
        }
        
        try pdfData.write(to: pdfURL)
        return pdfURL
    }
    
    /// Generate QR code image from URL string
    private static func generateQRCodeImage(from urlString: String, size: CGSize) -> UIImage? {
        return QRCodeGenerator.generate(from: urlString, size: size)
    }
}

