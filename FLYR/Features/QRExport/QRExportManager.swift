import Foundation
import UIKit

/// Main manager for QR code export operations
@MainActor
class QRExportManager {
    
    /// Export QR codes as ZIP file containing PNGs and CSV
    /// - Parameters:
    ///   - campaign: The campaign containing the QR codes
    ///   - qrCodes: Array of QR codes to export
    ///   - notes: Optional dictionary mapping QR code IDs to notes for CSV
    /// - Returns: URL of the created ZIP file
    /// - Throws: Error if export process fails
    static func export(
        campaign: CampaignV2,
        qrCodes: [QRCodeAddress],
        notes: [UUID: String]? = nil
    ) async throws -> URL {
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("qr_export")
        
        // Clean up existing export directory if it exists
        if FileManager.default.fileExists(atPath: exportDir.path) {
            try FileManager.default.removeItem(at: exportDir)
        }
        
        // Create export directory
        try FileManager.default.createDirectory(
            at: exportDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Generate PNG files and collect filenames
        // Use autoreleasepool to release memory after each image generation
        var filenames: [UUID: String] = [:]
        var lastError: Error?
        
        for qrCode in qrCodes {
            autoreleasepool {
                do {
                    let filename = try QRPNGGenerator.generatePNG(
                        url: qrCode.webURL,
                        qrId: qrCode.id,
                        address: qrCode.formatted,
                        outputDirectory: exportDir
                    )
                    filenames[qrCode.id] = filename
                } catch {
                    lastError = error
                }
            }
        }
        
        // Throw error if any occurred
        if let error = lastError {
            throw error
        }
        
        // Generate CSV file
        _ = try QRCSVBuilder.generateCSV(
            qrCodes: qrCodes,
            campaignName: campaign.name,
            filenames: filenames,
            notes: notes,
            outputDirectory: exportDir
        )
        
        // Create ZIP file
        let zipURL = try QRZipExporter.createZIP(
            sourceDirectory: exportDir,
            campaignName: campaign.name,
            outputURL: tempDir
        )
        
        // Clean up temp directory (keep ZIP file)
        try? FileManager.default.removeItem(at: exportDir)
        
        return zipURL
    }
    
    /// Export QR codes as single PDF file
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to include
    ///   - batchName: Name for the batch (used in filename)
    /// - Returns: URL of the created PDF file
    /// - Throws: Error if PDF generation fails
    static func exportAsPDF(
        qrCodes: [QRCode],
        batchName: String
    ) throws -> URL {
        // Build address dictionary
        var addresses: [UUID: String] = [:]
        for qrCode in qrCodes {
            addresses[qrCode.id] = qrCode.metadata?.entityName
        }
        
        return try QRPDFGenerator.generatePDF(
            qrCodes: qrCodes,
            batchName: batchName,
            addresses: addresses
        )
    }
    
    /// Present share sheet for exported ZIP file
    /// - Parameter zipURL: URL of the ZIP file to share
    static func presentShareSheet(for zipURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ [QR Export] Failed to get root view controller for share sheet")
            return
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [zipURL],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        rootViewController.present(activityVC, animated: true)
    }
    
    // MARK: - New Export Functions for QR Sets
    
    /// Export QR codes as individual PNG files
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to export
    ///   - batchName: Name for the batch
    /// - Returns: URL of the directory containing PNG files
    /// - Throws: Error if export fails
    static func exportAsPNG(qrCodes: [QRCode], batchName: String) throws -> URL {
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
        
        // Convert QRCode to QRCodeAddress for PNG export
        let addresses = qrCodes.compactMap { qrCode -> QRCodeAddress? in
            guard let addressId = qrCode.addressId else { return nil }
            let (_, deepLinkURL) = QRCodeAddress.generateURLs(for: addressId)
            return QRCodeAddress(
                id: qrCode.id,
                addressId: addressId,
                formatted: qrCode.metadata?.entityName ?? "QR Code",
                webURL: qrCode.qrUrl,
                deepLinkURL: deepLinkURL,
                createdAt: qrCode.createdAt
            )
        }
        
        guard !addresses.isEmpty else {
            throw NSError(domain: "QRExportManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid addresses found"])
        }
        
        _ = try PNGExportService.generatePNGs(
            addresses: addresses,
            outputDirectory: exportDir,
            useTransparentBackground: false
        )
        
        return exportDir
    }
    
    /// Export QR codes as PDF with grid layout
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to export
    ///   - batchName: Name for the batch
    ///   - gridSize: Optional grid size (defaults to auto)
    /// - Returns: URL of the created PDF file
    /// - Throws: Error if PDF generation fails
    static func exportAsPDF(qrCodes: [QRCode], batchName: String, gridSize: CGSize? = nil) throws -> URL {
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
        
        // Convert QRCode to QRCodeAddress for PDF export
        let addresses = qrCodes.compactMap { qrCode -> QRCodeAddress? in
            guard let addressId = qrCode.addressId else { return nil }
            let (_, deepLinkURL) = QRCodeAddress.generateURLs(for: addressId)
            return QRCodeAddress(
                id: qrCode.id,
                addressId: addressId,
                formatted: qrCode.metadata?.entityName ?? "QR Code",
                webURL: qrCode.qrUrl,
                deepLinkURL: deepLinkURL,
                createdAt: qrCode.createdAt
            )
        }
        
        guard !addresses.isEmpty else {
            throw NSError(domain: "QRExportManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid addresses found"])
        }
        
        return try PDFGridRenderer.generatePDF(
            addresses: addresses,
            batchName: batchName,
            outputURL: exportDir
        )
    }
    
    /// Export QR codes for Canva (CSV with address and QR filename mapping)
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to export
    ///   - batchName: Name for the batch
    /// - Returns: URL of the created CSV file
    /// - Throws: Error if CSV generation fails
    static func exportForCanva(qrCodes: [QRCode], batchName: String) throws -> URL {
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
        
        // Convert QRCode to QRCodeAddress
        let addresses = qrCodes.compactMap { qrCode -> QRCodeAddress? in
            guard let addressId = qrCode.addressId else { return nil }
            let (webURL, deepLinkURL) = QRCodeAddress.generateURLs(for: addressId)
            return QRCodeAddress(
                id: qrCode.id,
                addressId: addressId,
                formatted: qrCode.metadata?.entityName ?? "QR Code",
                webURL: qrCode.qrUrl,
                deepLinkURL: deepLinkURL,
                createdAt: qrCode.createdAt
            )
        }
        
        guard !addresses.isEmpty else {
            throw NSError(domain: "QRExportManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid addresses found"])
        }
        
        // Generate PNGs first (needed for CSV)
        let filenames = try PNGExportService.generatePNGs(
            addresses: addresses,
            outputDirectory: exportDir,
            useTransparentBackground: false
        )
        
        // Generate CSV
        let csvFilename = try CSVExportService.generateCSV(
            addresses: addresses,
            filenames: filenames,
            outputDirectory: exportDir,
            batchName: batchName
        )
        
        return exportDir.appendingPathComponent(csvFilename)
    }
    
    /// Export QR codes as ZIP archive containing PNGs and CSV
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to export
    ///   - batchName: Name for the batch
    /// - Returns: URL of the created ZIP file
    /// - Throws: Error if ZIP creation fails
    static func exportAsZIP(qrCodes: [QRCode], batchName: String) throws -> URL {
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
        
        // Convert QRCode to QRCodeAddress
        let addresses = qrCodes.compactMap { qrCode -> QRCodeAddress? in
            guard let addressId = qrCode.addressId else { return nil }
            let (webURL, deepLinkURL) = QRCodeAddress.generateURLs(for: addressId)
            return QRCodeAddress(
                id: qrCode.id,
                addressId: addressId,
                formatted: qrCode.metadata?.entityName ?? "QR Code",
                webURL: qrCode.qrUrl,
                deepLinkURL: deepLinkURL,
                createdAt: qrCode.createdAt
            )
        }
        
        guard !addresses.isEmpty else {
            throw NSError(domain: "QRExportManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid addresses found"])
        }
        
        // Generate PNGs
        let filenames = try PNGExportService.generatePNGs(
            addresses: addresses,
            outputDirectory: exportDir,
            useTransparentBackground: false
        )
        
        // Generate CSV
        let qrDirectory = exportDir.appendingPathComponent("qr", isDirectory: true)
        let csvFilename = try CSVExportService.generateCSV(
            addresses: addresses,
            filenames: filenames,
            outputDirectory: exportDir,
            batchName: batchName
        )
        
        let csvFile = exportDir.appendingPathComponent(csvFilename)
        
        // Create ZIP
        let zipURL = try ZIPArchiveService.createZIP(
            batchName: batchName,
            qrDirectory: qrDirectory,
            csvFile: csvFile,
            outputURL: tempDir
        )
        
        return zipURL
    }
    
    /// Generate thermal labels for QR codes
    /// - Parameters:
    ///   - qrCodes: Array of QR codes to generate labels for
    ///   - labelSize: Size of the thermal label
    /// - Returns: URL of the directory containing thermal label PNG files
    /// - Throws: Error if generation fails
    static func generateThermalLabels(qrCodes: [QRCode], labelSize: ThermalLabelSize) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("thermal_labels_\(UUID().uuidString)")
        
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
        
        // Generate thermal labels
        for qrCode in qrCodes {
            let address = qrCode.metadata?.entityName
            let campaignName = qrCode.metadata?.entityName
            
            let labelURL = try ThermalLabelGenerator.generate(
                url: qrCode.qrUrl,
                address: address,
                campaignName: campaignName,
                size: labelSize
            )
            
            // Move to export directory with descriptive name
            let filename = "thermal_\(qrCode.id.uuidString).png"
            let destinationURL = exportDir.appendingPathComponent(filename)
            try? FileManager.default.moveItem(at: labelURL, to: destinationURL)
        }
        
        return exportDir
    }
}

