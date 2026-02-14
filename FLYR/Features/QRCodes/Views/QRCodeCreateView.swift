import SwiftUI
import Foundation

/// QR Code Creation Screen - Apple HIG Redesign
/// Supports both Campaigns and Farms with Supabase persistence
struct QRCodeCreateView: View {
    @StateObject private var hook = UseQRCodeCreate()
    @State private var selectedSource: QRSourceType = .campaigns
    @State private var selectedQRCode: QRCode?
    @State private var showingCreateBatch = false
    @State private var showPrintQR = false
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Segmented Picker
                QRSourcePicker(selectedSource: $selectedSource)
                    .onChange(of: selectedSource) { _, _ in
                        hook.clearSelection()
                    }
                
                // Capsule Selector
                if selectedSource == .campaigns {
                    if hook.isLoadingCampaigns {
                        ProgressView()
                            .padding()
                    } else {
                        CampaignCapsuleSelector(
                            items: hook.campaigns,
                            selectedId: hook.selectedCampaignId,
                            onSelect: { campaignId in
                                Task {
                                    await hook.loadQRCodesForCampaign(campaignId)
                                }
                            }
                        )
                    }
                } else {
                    if hook.isLoadingFarms {
                        ProgressView()
                            .padding()
                    } else {
                        FarmCapsuleSelector(
                            items: hook.farms,
                            selectedId: hook.selectedFarmId,
                            onSelect: { farmId in
                                Task {
                                    await hook.loadQRCodesForFarm(farmId)
                                }
                            }
                        )
                    }
                }
                
                Divider()
                
                // Content Area
                if hook.isLoading {
                    ProgressView("Loading QR codes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hook.qrCodes.isEmpty {
                    QREmptyState(
                        message: hook.hasSelection
                            ? "No QR codes yet. Tap 'Create QR Code' to generate one."
                            : "Select a \(selectedSource.displayName.lowercased()) to create QR codes."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Show batches first
                            ForEach(hook.batches) { batch in
                                BatchCardView(
                                    batch: batch,
                                    onPreview: {
                                        previewBatch(batch)
                                    },
                                    onExport: {
                                        exportBatch(batch)
                                    },
                                    onPrint: {
                                        printBatch(batch)
                                    },
                                    onShare: {
                                        shareBatch(batch)
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                            
                            // Show individual QR codes (not part of batches) in grid
                            if !hook.individualQRCodes.isEmpty {
                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 160), spacing: 20)
                                ], spacing: 20) {
                                    ForEach(hook.individualQRCodes) { qrCode in
                                        QRCard(
                                            qr: qrCode,
                                            campaignName: hook.selectedEntityName,
                                            onPrint: {
                                                printQRCode(qrCode)
                                            },
                                            onTap: {
                                                selectedQRCode = qrCode
                                            }
                                        )
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 10)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
                
                // Create Button
                VStack(spacing: 0) {
                    Divider()
                    
                    Button {
                        showingCreateBatch = true
                    } label: {
                        HStack {
                            if hook.isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Create QR Code")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(hook.hasSelection ? Color.red : Color(.systemGray4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!hook.hasSelection || hook.isCreating)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Create QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Quick standalone QR creation (future feature)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await hook.loadCampaigns()
            await hook.loadFarms()
        }
        .sheet(item: $selectedQRCode) { qrCode in
            QRCodeDetailSheet(qrCode: qrCode, onUpdate: { updatedQRCode in
                // Update the QR code in the list
                if let index = hook.qrCodes.firstIndex(where: { $0.id == updatedQRCode.id }) {
                    hook.qrCodes[index] = updatedQRCode
                }
            })
        }
        .alert("Error", isPresented: Binding(
            get: { hook.errorMessage != nil },
            set: { if !$0 { hook.errorMessage = nil } }
        )) {
            Button("OK") {
                hook.errorMessage = nil
            }
        } message: {
            if let error = hook.errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showingCreateBatch) {
            if let campaignId = hook.selectedCampaignId {
                CreateBatchView(
                    campaignId: campaignId,
                    onBatchCreated: { batch in
                        Task {
                            // Reload QR codes to show the new batch
                            await hook.loadQRCodesForCampaign(campaignId)
                            
                            // Trigger export based on batch export format
                            await handleBatchExport(batch)
                        }
                    }
                )
            }
        }
        .navigationDestination(isPresented: $showPrintQR) {
            QRPrintViewV2()
        }
    }
    
    // MARK: - Actions
    
    private func exportQRCode(_ qrCode: QRCode) {
        // TODO: Implement export functionality
        print("Export QR code: \(qrCode.id)")
    }
    
    private func printQRCode(_ qrCode: QRCode) {
        showPrintQR = true
    }
    
    private func shareQRCode(_ qrCode: QRCode) {
        // TODO: Implement share functionality
        print("Share QR code: \(qrCode.id)")
    }
    
    // MARK: - Batch Actions
    
    private func previewBatch(_ batch: QRCodeBatch) {
        // Show PDF preview - use the first QR code's preview image
        if let firstQRCode = batch.qrCodes.first {
            selectedQRCode = firstQRCode
        }
    }
    
    private func exportBatch(_ batch: QRCodeBatch) {
        Task {
            do {
                let pdfURL = try QRExportManager.exportAsPDF(
                    qrCodes: batch.qrCodes,
                    batchName: batch.batchName
                )
                QRExportManager.presentShareSheet(for: pdfURL)
            } catch {
                hook.errorMessage = "Failed to export batch: \(error.localizedDescription)"
            }
        }
    }
    
    private func printBatch(_ batch: QRCodeBatch) {
        showPrintQR = true
    }
    
    private func shareBatch(_ batch: QRCodeBatch) {
        Task {
            do {
                let pdfURL = try QRExportManager.exportAsPDF(
                    qrCodes: batch.qrCodes,
                    batchName: batch.batchName
                )
                QRExportManager.presentShareSheet(for: pdfURL)
            } catch {
                hook.errorMessage = "Failed to share batch: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Batch Export Handler
    
    private func handleBatchExport(_ batch: Batch) async {
        // Fetch QR codes for this batch
        do {
            let qrCodes = try await QRRepository.shared.fetchQRCodesForBatch(batchId: batch.id)
            
            switch batch.exportFormat {
            case .pdf:
                let pdfURL = try QRExportManager.exportAsPDF(
                    qrCodes: qrCodes,
                    batchName: batch.name
                )
                QRExportManager.presentShareSheet(for: pdfURL)
                
            case .label3x3:
                let labelURL = try QRExportManager.generateThermalLabels(
                    qrCodes: qrCodes,
                    labelSize: ThermalLabelSize.size3x3
                )
                QRExportManager.presentShareSheet(for: labelURL)
                
            case .png:
                let pngURL = try QRExportManager.exportAsPNG(
                    qrCodes: qrCodes,
                    batchName: batch.name
                )
                QRExportManager.presentShareSheet(for: pngURL)
                
            case .canva:
                let canvaURL = try QRExportManager.exportForCanva(
                    qrCodes: qrCodes,
                    batchName: batch.name
                )
                QRExportManager.presentShareSheet(for: canvaURL)
            }
        } catch {
            hook.errorMessage = "Failed to export batch: \(error.localizedDescription)"
        }
    }
}

// MARK: - QR Code Detail Sheet

struct QRCodeDetailSheet: View {
    let qrCode: QRCode
    let onUpdate: (QRCode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    @State private var qrCodeName: String
    @State private var isPrinted: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    private let qrRepository = QRRepository.shared
    
    init(qrCode: QRCode, onUpdate: @escaping (QRCode) -> Void) {
        self.qrCode = qrCode
        self.onUpdate = onUpdate
        // If it's a batch, show batch name; otherwise show QR code name
        let displayName = qrCode.metadata?.batchName ?? qrCode.metadata?.name ?? ""
        _qrCodeName = State(initialValue: displayName)
        _isPrinted = State(initialValue: qrCode.metadata?.isPrinted ?? false)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // QR Code Image
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 300, height: 300)
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(radius: 8)
                    } else {
                        ProgressView()
                            .frame(width: 300, height: 300)
                    }
                    
                    // Name Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.flyrHeadline)
                        TextField("Enter QR code name", text: $qrCodeName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                saveChanges()
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Printed Toggle
                    HStack {
                        Text("Printed")
                            .font(.flyrHeadline)
                        Spacer()
                        Toggle("", isOn: $isPrinted)
                            .labelsHidden()
                            .onChange(of: isPrinted) { _, _ in
                                saveChanges()
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // QR URL Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QR URL")
                            .font(.flyrHeadline)
                        Text(qrCode.qrUrl)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Metadata
                    if let metadata = qrCode.metadata {
                        VStack(alignment: .leading, spacing: 12) {
                            if let entityName = metadata.entityName {
                                HStack {
                                    Text("Entity")
                                        .font(.flyrHeadline)
                                    Spacer()
                                    Text(entityName)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let addressCount = metadata.addressCount {
                                HStack {
                                    Text("Addresses")
                                        .font(.flyrHeadline)
                                    Spacer()
                                    Text("\(addressCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: shareQRCode) {
                            Label("Share QR Code", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                        
                        Button(action: exportQRCode) {
                            Label("Export QR Code", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                        
                        NavigationLink(destination: ThermalPrintView(
                            qrURL: qrCode.qrUrl,
                            address: qrCode.metadata?.entityName ?? "QR Code",
                            campaignName: qrCode.metadata?.entityName
                        )) {
                            Label("Print QR Label", systemImage: "printer")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                    }
                }
                .padding()
            }
            .navigationTitle(qrCode.metadata?.batchName != nil ? "Batch Preview" : "QR Code Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadQRImage()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    private func loadQRImage() {
        if let base64Image = qrCode.qrImage,
           let imageData = Data(base64Encoded: base64Image),
           let image = UIImage(data: imageData) {
            qrImage = image
        } else if let image = QRCodeGenerator.generate(from: qrCode.qrUrl, size: CGSize(width: 500, height: 500)) {
            qrImage = image
        }
    }
    
    private func saveChanges() {
        guard !isSaving else { return }
        
        isSaving = true
        Task {
            do {
                let updatedQRCode = try await qrRepository.updateQRCode(
                    id: qrCode.id,
                    name: qrCodeName.isEmpty ? nil : qrCodeName,
                    isPrinted: isPrinted
                )
                await MainActor.run {
                    onUpdate(updatedQRCode)
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save changes: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
    
    private func shareQRCode() {
        guard let qrImage = qrImage else { return }
        let activityVC = UIActivityViewController(activityItems: [qrImage, qrCode.qrUrl], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    private func exportQRCode() {
        guard let qrImage = qrImage else { return }
        let activityVC = UIActivityViewController(activityItems: [qrImage], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

// MARK: - Batch Name Sheet

struct BatchNameSheet: View {
    @Binding var batchName: String
    @Binding var generatePDF: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title and Description
                VStack(spacing: 12) {
                    Text("Name Your Batch")
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text("Give this batch a name.")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                // Text Field
                TextField("Batch Name", text: $batchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 17))
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                
                // PDF Info with Switch
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A PDF with all QR codes will be created.")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $generatePDF)
                            .labelsHidden()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onCreate()
                        dismiss()
                    }) {
                        Text("Create")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Extensions

extension QRSourceType {
    var displayName: String {
        rawValue
    }
}
