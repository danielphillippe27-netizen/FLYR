import Foundation
import UIKit
import PDFKit

/// Generates a single PDF file containing all QR codes with addresses
struct QRPDFGenerator {
    
    /// Generate a PDF with all QR codes, each showing address below
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to include
    ///   - batchName: Name for the batch (used in filename)
    ///   - addresses: Dictionary mapping QR code IDs to address strings
    /// - Returns: URL of the created PDF file
    static func generatePDF(
        qrCodes: [QRCode],
        batchName: String,
        addresses: [UUID: String]
    ) throws -> URL {
        let pdfMetaData = [
            kCGPDFContextCreator: "FLYR",
            kCGPDFContextAuthor: "FLYR App",
            kCGPDFContextTitle: batchName
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        // Page size: 8.5 x 11 inches (US Letter)
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        // QR code size on page (3x3 inches)
        let qrSize: CGFloat = 3.0 * 72.0
        let spacing: CGFloat = 0.5 * 72.0
        
        // Calculate layout: 2 QR codes per row, multiple rows per page
        let qrCodesPerRow = 2
        let qrCodesPerPage = 6 // 3 rows x 2 columns
        let margin: CGFloat = 0.5 * 72.0
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let tempDir = FileManager.default.temporaryDirectory
        let sanitizedBatchName = sanitizeFilename(batchName)
        let pdfURL = tempDir.appendingPathComponent("\(sanitizedBatchName)_QR_Codes.pdf")
        
        // Remove existing PDF if it exists
        if FileManager.default.fileExists(atPath: pdfURL.path) {
            try? FileManager.default.removeItem(at: pdfURL)
        }
        
        let pdfData = renderer.pdfData { context in
            var qrIndex = 0
            var hasStartedFirstPage = false
            
            for qrCode in qrCodes {
                // Start new page if needed
                if qrIndex % qrCodesPerPage == 0 {
                    if hasStartedFirstPage {
                        context.beginPage()
                    } else {
                        hasStartedFirstPage = true
                    }
                }
                
                let positionInPage = qrIndex % qrCodesPerPage
                let row = positionInPage / qrCodesPerRow
                let col = positionInPage % qrCodesPerRow
                
                // Calculate position
                let x = margin + CGFloat(col) * (qrSize + spacing)
                let y = margin + CGFloat(row) * (qrSize + spacing + 25) // Extra space for address text
                
                // Generate QR code image
                if let qrImage = generateQRCodeImage(qrCode: qrCode, size: CGSize(width: qrSize, height: qrSize)) {
                    // Draw QR code
                    qrImage.draw(in: CGRect(x: x, y: y, width: qrSize, height: qrSize))
                    
                    // Draw address below QR code
                    let address = addresses[qrCode.id] ?? qrCode.metadata?.entityName ?? "Unknown Address"
                    let addressRect = CGRect(x: x, y: y + qrSize + 5, width: qrSize, height: 20)
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    paragraphStyle.lineBreakMode = .byTruncatingTail
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    address.draw(in: addressRect, withAttributes: attributes)
                }
                
                qrIndex += 1
            }
        }
        
        try pdfData.write(to: pdfURL)
        return pdfURL
    }
    
    private static func generateQRCodeImage(qrCode: QRCode, size: CGSize) -> UIImage? {
        // Try to use existing base64 image first
        if let base64Image = qrCode.qrImage,
           let imageData = Data(base64Encoded: base64Image),
           let image = UIImage(data: imageData) {
            return image.resized(to: size)
        }
        
        // Generate new QR code
        return QRCodeGenerator.generate(from: qrCode.qrUrl, size: size)
    }
    
    private static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:?<>\\|*\"")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}



