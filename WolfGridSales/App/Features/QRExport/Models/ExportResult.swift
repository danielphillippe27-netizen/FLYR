import Foundation

/// Result of an export operation containing URLs to all generated files
public struct ExportResult {
    /// URL to the PDF grid file (if generated)
    public let pdfGridURL: URL?
    
    /// URL to the PDF single file (if generated)
    public let pdfSingleURL: URL?
    
    /// URL to the ZIP archive file (if generated)
    public let zipURL: URL?
    
    /// URL to the directory containing PNG files (if generated)
    public let pngDirectoryURL: URL?
    
    /// URL to the CSV file (if generated)
    public let csvURL: URL?
    
    /// Name of the batch
    public let batchName: String
    
    /// Campaign ID associated with this export
    public let campaignId: UUID
    
    /// Number of addresses exported
    public let addressCount: Int
    
    public init(
        pdfGridURL: URL? = nil,
        pdfSingleURL: URL? = nil,
        zipURL: URL? = nil,
        pngDirectoryURL: URL? = nil,
        csvURL: URL? = nil,
        batchName: String,
        campaignId: UUID,
        addressCount: Int
    ) {
        self.pdfGridURL = pdfGridURL
        self.pdfSingleURL = pdfSingleURL
        self.zipURL = zipURL
        self.pngDirectoryURL = pngDirectoryURL
        self.csvURL = csvURL
        self.batchName = batchName
        self.campaignId = campaignId
        self.addressCount = addressCount
    }
    
    /// Check if any files were generated
    public var hasFiles: Bool {
        pdfGridURL != nil || pdfSingleURL != nil || zipURL != nil || pngDirectoryURL != nil || csvURL != nil
    }
}

