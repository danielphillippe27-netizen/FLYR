import Foundation
import SwiftUI
import Combine
import PDFKit

/// Hook for QR Code creation
/// Handles campaign/farm selection and QR code generation with Supabase persistence
@MainActor
class UseQRCodeCreate: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var farms: [FarmListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var selectedFarmId: UUID?
    @Published var qrCodes: [QRCode] = []
    @Published var batches: [QRCodeBatch] = []
    @Published var isLoading = false
    @Published var isLoadingCampaigns = false
    @Published var isLoadingFarms = false
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    private let qrRepository = QRRepository.shared
    private let qrCodeAPI = QRCodeAPI.shared
    
    // MARK: - Load Data
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        errorMessage = nil
        defer { isLoadingCampaigns = false }
        
        do {
            campaigns = try await qrCodeAPI.fetchCampaigns(workspaceId: WorkspaceContext.shared.workspaceId)
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [QR Create] Error loading campaigns: \(error)")
        }
    }
    
    func loadFarms() async {
        isLoadingFarms = true
        errorMessage = nil
        defer { isLoadingFarms = false }
        
        do {
            let farmRows = try await qrRepository.fetchFarms()
            farms = farmRows.map { $0.toFarmListItem() }
        } catch {
            errorMessage = "Failed to load farms: \(error.localizedDescription)"
            print("❌ [QR Create] Error loading farms: \(error)")
        }
    }
    
    // MARK: - Load QR Codes
    
    func loadQRCodesForCampaign(_ campaignId: UUID) async {
        isLoading = true
        errorMessage = nil
        selectedCampaignId = campaignId
        selectedFarmId = nil
        defer { isLoading = false }
        
        do {
            qrCodes = try await qrRepository.fetchQRCodesForCampaign(campaignId)
            updateBatches()
        } catch {
            errorMessage = "Failed to load QR codes: \(error.localizedDescription)"
            print("❌ [QR Create] Error loading QR codes: \(error)")
        }
    }
    
    func loadQRCodesForFarm(_ farmId: UUID) async {
        isLoading = true
        errorMessage = nil
        selectedFarmId = farmId
        selectedCampaignId = nil
        defer { isLoading = false }
        
        do {
            qrCodes = try await qrRepository.fetchQRCodesForFarm(farmId)
            updateBatches()
        } catch {
            errorMessage = "Failed to load QR codes: \(error.localizedDescription)"
            print("❌ [QR Create] Error loading QR codes: \(error)")
        }
    }
    
    // MARK: - Create QR Code
    
    func createQRCode(batchName: String? = nil) async {
        guard let campaignId = selectedCampaignId else {
            errorMessage = "Please select a campaign"
            return
        }
        
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        
        do {
            // For campaigns, create QR codes for all addresses
            let campaignsAPI = CampaignsAPI.shared
            let addresses = try await campaignsAPI.fetchAddresses(campaignId: campaignId)
            
            guard !addresses.isEmpty else {
                errorMessage = "No addresses found for this campaign"
                return
            }
            
            // Create QR codes for all addresses
            let addressTuples = addresses.map { (id: $0.id, formatted: $0.formatted) }
            let createdQRCodes = try await qrRepository.createQRCodesForCampaignAddresses(
                campaignId: campaignId,
                addresses: addressTuples,
                batchName: batchName
            )
            
            print("✅ [QR Create] Created \(createdQRCodes.count) QR codes for campaign")
            
            // If batch name provided, generate PDF and save as preview
            if let batchName = batchName, !batchName.isEmpty, !createdQRCodes.isEmpty {
                await saveBatchPDFPreview(batchName: batchName, qrCodes: createdQRCodes)
                await exportBatchAsPDF(batchName: batchName, qrCodes: createdQRCodes)
            }
            
            // Reload QR codes to show the new ones
            await loadQRCodesForCampaign(campaignId)
        } catch {
            errorMessage = "Failed to create QR codes: \(error.localizedDescription)"
            print("❌ [QR Create] Error creating QR codes: \(error)")
        }
    }
    
    // MARK: - Export Batch
    
    func exportBatchAsPDF(batchName: String, qrCodes: [QRCode]) async {
        do {
            let pdfURL = try QRExportManager.exportAsPDF(
                qrCodes: qrCodes,
                batchName: batchName
            )
            
            // Present share sheet
            QRExportManager.presentShareSheet(for: pdfURL)
        } catch {
            errorMessage = "Failed to export PDF: \(error.localizedDescription)"
            print("❌ [QR Create] Error exporting PDF: \(error)")
        }
    }
    
    /// Save PDF first page as preview image for batch QR codes
    func saveBatchPDFPreview(batchName: String, qrCodes: [QRCode]) async {
        do {
            // Generate PDF
            let pdfURL = try QRExportManager.exportAsPDF(
                qrCodes: qrCodes,
                batchName: batchName
            )
            
            // Convert first page of PDF to image
            guard let pdfPreviewImage = convertPDFFirstPageToImage(pdfURL: pdfURL),
                  let previewBase64 = pdfPreviewImage.pngData()?.base64EncodedString() else {
                print("⚠️ [QR Create] Failed to generate PDF preview")
                return
            }
            
            // Update the first QR code in the batch with the PDF preview
            if let firstQRCode = qrCodes.first {
                // Update the QR code's qr_image with the PDF preview
                let updatedQRCode = try await qrRepository.updateQRCodePreview(
                    id: firstQRCode.id,
                    previewImage: previewBase64
                )
                print("✅ [QR Create] Saved PDF preview for batch: \(batchName)")
            }
        } catch {
            print("⚠️ [QR Create] Failed to save PDF preview: \(error)")
        }
    }
    
    /// Convert first page of PDF to UIImage
    private func convertPDFFirstPageToImage(pdfURL: URL) -> UIImage? {
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let firstPage = pdfDocument.page(at: 0) else {
            return nil
        }
        
        // Render PDF page to image at a reasonable size for preview
        let pageRect = firstPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // For retina display
        let imageSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: 0, y: imageSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            firstPage.draw(with: .mediaBox, to: context.cgContext)
        }
        
        return image
    }
    
    // MARK: - Update QR Code
    
    func updateQRCode(id: UUID, name: String?, isPrinted: Bool?) async {
        errorMessage = nil
        
        do {
            let updatedQRCode = try await qrRepository.updateQRCode(id: id, name: name, isPrinted: isPrinted)
            
            // Update the QR code in the local array
            if let index = qrCodes.firstIndex(where: { $0.id == id }) {
                qrCodes[index] = updatedQRCode
            }
        } catch {
            errorMessage = "Failed to update QR code: \(error.localizedDescription)"
            print("❌ [QR Create] Error updating QR code: \(error)")
        }
    }
    
    // MARK: - Clear Selection
    
    func clearSelection() {
        selectedCampaignId = nil
        selectedFarmId = nil
        qrCodes = []
    }
    
    func clearQRCodes() {
        qrCodes = []
        selectedCampaignId = nil
        selectedFarmId = nil
    }
    
    // MARK: - Computed Properties
    
    var hasSelection: Bool {
        selectedCampaignId != nil || selectedFarmId != nil
    }
    
    var selectedEntityName: String? {
        if let campaignId = selectedCampaignId {
            return campaigns.first(where: { $0.id == campaignId })?.name
        } else if let farmId = selectedFarmId {
            return farms.first(where: { $0.id == farmId })?.name
        }
        return nil
    }
    
    // MARK: - Batch Grouping
    
    /// Group QR codes by batch name
    func updateBatches() {
        // Group QR codes by batch name
        let grouped = Dictionary(grouping: qrCodes) { qrCode in
            qrCode.metadata?.batchName ?? ""
        }
        
        // Create batches, excluding empty batch names (individual QR codes)
        batches = grouped.compactMap { batchName, codes in
            guard !batchName.isEmpty else { return nil }
            return QRCodeBatch(batchName: batchName, qrCodes: codes)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get individual QR codes (not part of any batch)
    var individualQRCodes: [QRCode] {
        qrCodes.filter { $0.metadata?.batchName == nil || $0.metadata?.batchName?.isEmpty == true }
    }
}
