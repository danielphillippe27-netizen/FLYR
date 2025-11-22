import Foundation
import UIKit

/// Main orchestrator for all export operations
/// Coordinates PDF, PNG, CSV, and ZIP generation
actor ExportManager {
    static let shared = ExportManager()
    
    private init() {}
    
    /// Export addresses in the specified mode
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - batchName: Name for the batch
    ///   - addresses: Array of addresses to export
    ///   - mode: Export mode (pdfGrid, pdfSingle, pngOnly, zipArchive)
    ///   - uploadToSupabase: Whether to upload to Supabase after export (default: false)
    /// - Returns: ExportResult with URLs to all generated files
    /// - Throws: ExportError if export fails
    func export(
        campaignId: UUID,
        batchName: String,
        addresses: [QRCodeAddress],
        mode: ExportMode,
        uploadToSupabase: Bool = false
    ) async throws -> ExportResult {
        guard !addresses.isEmpty else {
            throw ExportError.invalidAddresses
        }
        
        guard !batchName.isEmpty else {
            throw ExportError.invalidBatchName
        }
        
        // Create temp directory for export
        let tempDir = FileManager.default.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("qr_export_\(UUID().uuidString)")
        
        // Clean up existing export directory if it exists
        if FileManager.default.fileExists(atPath: exportDir.path) {
            try? FileManager.default.removeItem(at: exportDir)
        }
        
        // Create export directory
        try FileManager.default.createDirectory(
            at: exportDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        defer {
            // Cleanup temp directory after export (unless uploading to Supabase)
            if !uploadToSupabase {
                try? FileManager.default.removeItem(at: exportDir)
            }
        }
        
        var pdfGridURL: URL?
        var pdfSingleURL: URL?
        var zipURL: URL?
        var pngDirectoryURL: URL?
        var csvURL: URL?
        
        // Generate exports based on mode
        switch mode {
        case .pdfGrid:
            pdfGridURL = try PDFGridRenderer.generatePDF(
                addresses: addresses,
                batchName: batchName,
                outputURL: exportDir
            )
            
        case .pdfSingle:
            pdfSingleURL = try PDFSingleRenderer.generatePDF(
                addresses: addresses,
                batchName: batchName,
                outputURL: exportDir
            )
            
        case .pngOnly:
            // Generate PNGs
            let pngDir = exportDir.appendingPathComponent("qr", isDirectory: true)
            _ = try PNGExportService.generatePNGs(
                addresses: addresses,
                outputDirectory: exportDir,
                useTransparentBackground: false
            )
            pngDirectoryURL = pngDir
            
        case .zipArchive:
            // Generate PNGs
            let pngFilenames = try PNGExportService.generatePNGs(
                addresses: addresses,
                outputDirectory: exportDir,
                useTransparentBackground: false
            )
            
            // Generate CSV
            let csvFilename = try CSVExportService.generateCSV(
                addresses: addresses,
                filenames: pngFilenames,
                outputDirectory: exportDir,
                batchName: batchName
            )
            csvURL = exportDir.appendingPathComponent(csvFilename)
            
            // Create ZIP
            let qrDirectory = exportDir
            zipURL = try ZIPArchiveService.createZIP(
                batchName: batchName,
                qrDirectory: qrDirectory,
                csvFile: csvURL!,
                outputURL: exportDir
            )
            
            // Set PNG directory URL
            pngDirectoryURL = qrDirectory.appendingPathComponent("qr", isDirectory: true)
        }
        
        // Create result
        let result = ExportResult(
            pdfGridURL: pdfGridURL,
            pdfSingleURL: pdfSingleURL,
            zipURL: zipURL,
            pngDirectoryURL: pngDirectoryURL,
            csvURL: csvURL,
            batchName: batchName,
            campaignId: campaignId,
            addressCount: addresses.count
        )
        
        // Upload to Supabase if requested
        if uploadToSupabase {
            let uploadService = SupabaseUploadService.shared
            return try await uploadService.uploadExport(
                campaignId: campaignId,
                batchName: batchName,
                exportResult: result
            )
        }
        
        return result
    }
    
    /// Export in multiple modes at once
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - batchName: Name for the batch
    ///   - addresses: Array of addresses to export
    ///   - modes: Array of export modes to generate
    ///   - uploadToSupabase: Whether to upload to Supabase after export
    /// - Returns: ExportResult with URLs to all generated files
    /// - Throws: ExportError if export fails
    func exportMultiple(
        campaignId: UUID,
        batchName: String,
        addresses: [QRCodeAddress],
        modes: [ExportMode],
        uploadToSupabase: Bool = false
    ) async throws -> ExportResult {
        guard !addresses.isEmpty else {
            throw ExportError.invalidAddresses
        }
        
        guard !batchName.isEmpty else {
            throw ExportError.invalidBatchName
        }
        
        // Create temp directory for export
        let tempDir = FileManager.default.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("qr_export_\(UUID().uuidString)")
        
        // Clean up existing export directory if it exists
        if FileManager.default.fileExists(atPath: exportDir.path) {
            try? FileManager.default.removeItem(at: exportDir)
        }
        
        // Create export directory
        try FileManager.default.createDirectory(
            at: exportDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        defer {
            // Cleanup temp directory after export (unless uploading to Supabase)
            if !uploadToSupabase {
                try? FileManager.default.removeItem(at: exportDir)
            }
        }
        
        var pdfGridURL: URL?
        var pdfSingleURL: URL?
        var zipURL: URL?
        var pngDirectoryURL: URL?
        var csvURL: URL?
        var pngFilenames: [UUID: String] = [:]
        
        // Generate PNGs if needed for ZIP or PNG-only mode
        let needsPNGs = modes.contains(.pngOnly) || modes.contains(.zipArchive)
        if needsPNGs {
            pngFilenames = try PNGExportService.generatePNGs(
                addresses: addresses,
                outputDirectory: exportDir,
                useTransparentBackground: false
            )
            pngDirectoryURL = exportDir.appendingPathComponent("qr", isDirectory: true)
        }
        
        // Generate PDF Grid if requested
        if modes.contains(.pdfGrid) {
            pdfGridURL = try PDFGridRenderer.generatePDF(
                addresses: addresses,
                batchName: batchName,
                outputURL: exportDir
            )
        }
        
        // Generate PDF Single if requested
        if modes.contains(.pdfSingle) {
            pdfSingleURL = try PDFSingleRenderer.generatePDF(
                addresses: addresses,
                batchName: batchName,
                outputURL: exportDir
            )
        }
        
        // Generate CSV if needed for ZIP
        if modes.contains(.zipArchive) {
            let csvFilename = try CSVExportService.generateCSV(
                addresses: addresses,
                filenames: pngFilenames,
                outputDirectory: exportDir,
                batchName: batchName
            )
            csvURL = exportDir.appendingPathComponent(csvFilename)
            
            // Create ZIP
            let qrDirectory = exportDir
            zipURL = try ZIPArchiveService.createZIP(
                batchName: batchName,
                qrDirectory: qrDirectory,
                csvFile: csvURL!,
                outputURL: exportDir
            )
        }
        
        // Create result
        let result = ExportResult(
            pdfGridURL: pdfGridURL,
            pdfSingleURL: pdfSingleURL,
            zipURL: zipURL,
            pngDirectoryURL: pngDirectoryURL,
            csvURL: csvURL,
            batchName: batchName,
            campaignId: campaignId,
            addressCount: addresses.count
        )
        
        // Upload to Supabase if requested
        if uploadToSupabase {
            let uploadService = SupabaseUploadService.shared
            return try await uploadService.uploadExport(
                campaignId: campaignId,
                batchName: batchName,
                exportResult: result
            )
        }
        
        return result
    }
}

