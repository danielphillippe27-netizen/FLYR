import Foundation

/// Represents a batch of QR codes grouped by batch name
public struct QRCodeBatch: Identifiable, Equatable {
    public let id: String // batch name
    public let batchName: String
    public let qrCodes: [QRCode]
    public let createdAt: Date
    
    public init(batchName: String, qrCodes: [QRCode]) {
        self.id = batchName
        self.batchName = batchName
        self.qrCodes = qrCodes
        // Use the earliest creation date from the QR codes
        self.createdAt = qrCodes.map { $0.createdAt }.min() ?? Date()
    }
    
    /// Get the preview image from the first QR code (which should have the PDF preview)
    public var previewImage: String? {
        qrCodes.first?.qrImage
    }
    
    /// Get the count of QR codes in the batch
    public var count: Int {
        qrCodes.count
    }
}

