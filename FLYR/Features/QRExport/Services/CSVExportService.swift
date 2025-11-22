import Foundation

/// Creates Canva-compatible CSV files for bulk QR code imports
struct CSVExportService {
    
    /// Generate CSV file with address and QR code filename mapping
    /// Format: address,qr
    /// Example: 161 Sprucewood Crescent,qr/161_sprucewood_crescent.png
    /// - Parameters:
    ///   - addresses: Array of addresses
    ///   - filenames: Dictionary mapping address IDs to PNG filenames
    ///   - outputDirectory: Directory where CSV should be saved
    ///   - batchName: Name for the batch (used in filename)
    /// - Returns: Filename of the generated CSV
    /// - Throws: ExportError if generation fails
    static func generateCSV(
        addresses: [QRCodeAddress],
        filenames: [UUID: String],
        outputDirectory: URL,
        batchName: String
    ) throws -> String {
        guard !addresses.isEmpty else {
            throw ExportError.invalidAddresses
        }
        
        // Build CSV content
        var csvLines: [String] = []
        
        // Header row
        csvLines.append("address,qr")
        
        // Data rows
        for address in addresses {
            let addressField = escapeCSVField(address.formatted)
            let qrFilename = filenames[address.id] ?? "\(StringSlugifier.slugify(address.formatted)).png"
            let qrPath = "qr/\(qrFilename)"
            let qrField = escapeCSVField(qrPath)
            
            csvLines.append("\(addressField),\(qrField)")
        }
        
        // Join all lines
        let csvContent = csvLines.joined(separator: "\n")
        
        // Generate filename
        let sanitizedBatchName = StringSlugifier.slugify(batchName)
        let filename = "\(sanitizedBatchName)_batch.csv"
        let fileURL = outputDirectory.appendingPathComponent(filename)
        
        // Write to file as UTF-8 (no BOM)
        guard let csvData = csvContent.data(using: .utf8) else {
            throw ExportError.csvGenerationFailed("Failed to encode CSV content as UTF-8")
        }
        
        try csvData.write(to: fileURL)
        
        return filename
    }
    
    /// Escape CSV field (handle commas, quotes, newlines)
    /// - Parameter field: Field value to escape
    /// - Returns: Escaped field value
    private static func escapeCSVField(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

