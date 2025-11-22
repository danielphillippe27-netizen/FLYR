import Foundation

/// Builds CSV metadata file for QR code exports
struct QRCSVBuilder {
    
    /// Generate CSV file with QR code metadata
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to include
    ///   - campaignName: Name of the campaign
    ///   - filenames: Dictionary mapping QR code IDs to their PNG filenames
    ///   - notes: Optional dictionary mapping QR code IDs to notes
    ///   - outputDirectory: Directory to save the CSV file
    /// - Returns: The filename of the generated CSV file
    /// - Throws: Error if CSV generation or file writing fails
    static func generateCSV(
        qrCodes: [QRCodeAddress],
        campaignName: String,
        filenames: [UUID: String],
        notes: [UUID: String]? = nil,
        outputDirectory: URL
    ) throws -> String {
        let filename = "qr_export.csv"
        let fileURL = outputDirectory.appendingPathComponent(filename)
        
        // Build CSV content
        var csvLines: [String] = []
        
        // Header row
        csvLines.append("address,url,filename,campaign,notes")
        
        // Data rows
        for qrCode in qrCodes {
            let address = escapeCSVField(qrCode.formatted)
            let url = escapeCSVField(qrCode.webURL)
            let filename = filenames[qrCode.id] ?? "qr_\(qrCode.id.uuidString).png"
            let campaign = escapeCSVField(campaignName)
            let note = notes?[qrCode.id] ?? ""
            let escapedNote = escapeCSVField(note)
            
            csvLines.append("\(address),\(url),\(filename),\(campaign),\(escapedNote)")
        }
        
        // Join all lines
        let csvContent = csvLines.joined(separator: "\n")
        
        // Write to file as UTF-8 (no BOM)
        guard let csvData = csvContent.data(using: .utf8) else {
            throw QRExportError.csvGenerationFailed
        }
        
        try csvData.write(to: fileURL)
        
        return filename
    }
    
    /// Escape CSV field (handle commas, quotes, newlines)
    private static func escapeCSVField(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

