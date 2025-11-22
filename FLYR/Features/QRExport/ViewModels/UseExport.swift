import Foundation
import SwiftUI
import Combine

/// Hook for managing export state and operations
@MainActor
class UseExport: ObservableObject {
    @Published var isExporting = false
    @Published var progress: Double = 0.0
    @Published var errorMessage: String?
    @Published var exportResult: ExportResult?
    @Published var isUploading = false
    
    private let exportManager = ExportManager.shared
    
    /// Export addresses in the specified mode
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - batchName: Name for the batch
    ///   - addresses: Array of addresses to export
    ///   - mode: Export mode
    ///   - uploadToSupabase: Whether to upload to Supabase after export
    func export(
        campaignId: UUID,
        batchName: String,
        addresses: [QRCodeAddress],
        mode: ExportMode,
        uploadToSupabase: Bool = false
    ) async {
        isExporting = true
        progress = 0.0
        errorMessage = nil
        exportResult = nil
        
        defer {
            isExporting = false
            isUploading = false
        }
        
        do {
            // Update progress: 0-80% for export, 80-100% for upload
            progress = 0.1
            
            let result = try await exportManager.export(
                campaignId: campaignId,
                batchName: batchName,
                addresses: addresses,
                mode: mode,
                uploadToSupabase: uploadToSupabase
            )
            
            progress = uploadToSupabase ? 0.8 : 1.0
            
            if uploadToSupabase {
                isUploading = true
                // Upload is handled inside exportManager, but we can show progress
                progress = 0.9
            }
            
            progress = 1.0
            exportResult = result
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Export] Error: \(error)")
        }
    }
    
    /// Export in multiple modes at once
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - batchName: Name for the batch
    ///   - addresses: Array of addresses to export
    ///   - modes: Array of export modes
    ///   - uploadToSupabase: Whether to upload to Supabase after export
    func exportMultiple(
        campaignId: UUID,
        batchName: String,
        addresses: [QRCodeAddress],
        modes: [ExportMode],
        uploadToSupabase: Bool = false
    ) async {
        isExporting = true
        progress = 0.0
        errorMessage = nil
        exportResult = nil
        
        defer {
            isExporting = false
            isUploading = false
        }
        
        do {
            progress = 0.1
            
            let result = try await exportManager.exportMultiple(
                campaignId: campaignId,
                batchName: batchName,
                addresses: addresses,
                modes: modes,
                uploadToSupabase: uploadToSupabase
            )
            
            progress = uploadToSupabase ? 0.8 : 1.0
            
            if uploadToSupabase {
                isUploading = true
                progress = 0.9
            }
            
            progress = 1.0
            exportResult = result
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Export] Error: \(error)")
        }
    }
    
    /// Cancel export (if possible)
    func cancelExport() {
        // Note: Current implementation doesn't support cancellation
        // This is a placeholder for future async cancellation support
        isExporting = false
        isUploading = false
        progress = 0.0
    }
    
    /// Clear export result and error
    func clear() {
        exportResult = nil
        errorMessage = nil
        progress = 0.0
    }
}

