import SwiftUI

/// Comprehensive export options sheet for QR Sets
struct QRExportOptionsSheet: View {
    let qrSetId: UUID
    let qrSetName: String
    let onDismiss: () -> Void
    
    @StateObject private var hook = UseQRPrintV2()
    @State private var qrCodes: [QRCode] = []
    @State private var isLoadingCodes = false
    
    // Export type selection
    @State private var selectedExportType: ExportType = .standard
    
    // Thermal printing options
    @State private var selectedThermalSize: ThermalLabelSize = .size2x2
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""
    @State private var testPrintOne = false
    
    // Standard export options
    @State private var selectedStandardExport: StandardExport = .png
    
    // Advanced options
    @State private var filenameMode: FilenameMode = .address
    @State private var includeMetadata = false
    
    // Export state
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportError: String?
    @State private var exportedURL: URL?
    
    enum ExportType: String, CaseIterable {
        case thermal = "Thermal Printing"
        case standard = "Standard Exports"
        case advanced = "Advanced"
        
        var icon: String {
            switch self {
            case .thermal: return "printer"
            case .standard: return "square.grid.3x3"
            case .advanced: return "gearshape"
            }
        }
    }
    
    enum StandardExport: String, CaseIterable {
        case png = "PNG Files"
        case pdf = "PDF Grid"
        case zip = "ZIP Archive"
        case csv = "CSV for Canva"
        
        var icon: String {
            switch self {
            case .png: return "photo"
            case .pdf: return "doc.text"
            case .zip: return "archivebox"
            case .csv: return "tablecells"
            }
        }
    }
    
    enum FilenameMode: String, CaseIterable {
        case id = "ID"
        case address = "Address"
        case streetNumber = "Street Number"
        case campaignAddress = "Campaign + Address"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoadingCodes {
                    ProgressView("Loading QR codes...")
                } else if isExporting {
                    VStack(spacing: 24) {
                        ProgressView(value: exportProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        
                        Text("Exporting...")
                            .font(.flyrHeadline)
                            .foregroundStyle(.secondary)
                        
                        Text("\(Int(exportProgress * 100))%")
                            .font(.flyrTitle2)
                            .fontWeight(.semibold)
                    }
                    .padding()
                } else if let exportedURL = exportedURL {
                    // Export complete
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        
                        Text("Export Complete")
                            .font(.flyrTitle2)
                            .fontWeight(.semibold)
                        
                        Button("Share") {
                            shareFile(url: exportedURL)
                        }
                        .primaryButton()
                        .padding(.horizontal)
                        
                        Button("Done") {
                            self.exportedURL = nil
                            onDismiss()
                        }
                        .secondaryButton()
                        .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            VStack(spacing: 8) {
                                Text("Export QR Codes")
                                    .font(.system(size: 28, weight: .bold))
                                
                                Text(qrSetName)
                                    .font(.flyrSubheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                            
                            // Export type selector
                            Picker("Export Type", selection: $selectedExportType) {
                                ForEach(ExportType.allCases, id: \.self) { type in
                                    Label(type.rawValue, systemImage: type.icon)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            
                            // Content based on selected type
                            Group {
                                switch selectedExportType {
                                case .thermal:
                                    thermalExportOptions
                                case .standard:
                                    standardExportOptions
                                case .advanced:
                                    advancedExportOptions
                                }
                            }
                            .padding(.horizontal)
                            
                            // Export button
                            Button {
                                performExport()
                            } label: {
                                Text("Export")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(canExport ? Color.accent : Color(.systemGray4))
                                    .cornerRadius(12)
                            }
                            .disabled(!canExport || isExporting)
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") {
                    exportError = nil
                }
            } message: {
                if let error = exportError {
                    Text(error)
                }
            }
        }
        .task {
            await loadQRCodes()
        }
    }
    
    // MARK: - Thermal Export Options
    
    private var thermalExportOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Thermal Printing")
                .font(.flyrHeadline)
            
            // Label size selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Label Size")
                    .font(.flyrSubheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Label Size", selection: $selectedThermalSize) {
                    Text("2×2 inches").tag(ThermalLabelSize.size2x2)
                    Text("3×3 inches").tag(ThermalLabelSize.size3x3)
                    Text("Custom").tag(ThermalLabelSize.size2x2) // Placeholder
                }
                .pickerStyle(.segmented)
            }
            
            // Custom dimensions (if custom selected)
            // Note: Full custom dimension support would require extending ThermalLabelSize
            
            // Test print option
            Toggle("Test Print 1 Label", isOn: $testPrintOne)
                .toggleStyle(SwitchToggleStyle(tint: .accent))
            
            // Munbyn integration info
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Compatible with Munbyn and other thermal printers")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Standard Export Options
    
    private var standardExportOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Standard Exports")
                .font(.flyrHeadline)
            
            VStack(spacing: 12) {
                ForEach(StandardExport.allCases, id: \.self) { export in
                    Button {
                        selectedStandardExport = export
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: export.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(selectedStandardExport == export ? .white : .accent)
                                .frame(width: 44, height: 44)
                                .background(selectedStandardExport == export ? Color.accent.opacity(0.2) : Color(.systemGray6))
                                .cornerRadius(12)
                            
                            Text(export.rawValue)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            if selectedStandardExport == export {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.accent)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedStandardExport == export ? Color.accent.opacity(0.1) : Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedStandardExport == export ? Color.accent : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Advanced Export Options
    
    private var advancedExportOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Advanced Options")
                .font(.flyrHeadline)
            
            // Filename mode
            VStack(alignment: .leading, spacing: 12) {
                Text("Filename Mode")
                    .font(.flyrSubheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Filename Mode", selection: $filenameMode) {
                    ForEach(FilenameMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Include metadata toggle
            Toggle("Include Address Metadata", isOn: $includeMetadata)
                .toggleStyle(SwitchToggleStyle(tint: .accent))
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var canExport: Bool {
        !qrCodes.isEmpty && !isExporting
    }
    
    // MARK: - Actions
    
    private func loadQRCodes() async {
        isLoadingCodes = true
        defer { isLoadingCodes = false }
        
        qrCodes = await hook.loadQRCodesForSet(setId: qrSetId)
    }
    
    private func performExport() {
        guard !qrCodes.isEmpty else { return }
        
        isExporting = true
        exportProgress = 0.0
        
        Task {
            do {
                let url: URL
                
                switch selectedExportType {
                case .thermal:
                    // If test print, only generate one label
                    let codesToExport = testPrintOne ? Array(qrCodes.prefix(1)) : qrCodes
                    url = try QRExportManager.generateThermalLabels(
                        qrCodes: codesToExport,
                        labelSize: selectedThermalSize
                    )
                    
                case .standard:
                    switch selectedStandardExport {
                    case .png:
                        url = try QRExportManager.exportAsPNG(qrCodes: qrCodes, batchName: qrSetName)
                    case .pdf:
                        url = try QRExportManager.exportAsPDF(qrCodes: qrCodes, batchName: qrSetName)
                    case .zip:
                        url = try QRExportManager.exportAsZIP(qrCodes: qrCodes, batchName: qrSetName)
                    case .csv:
                        url = try QRExportManager.exportForCanva(qrCodes: qrCodes, batchName: qrSetName)
                    }
                    
                case .advanced:
                    // For advanced, default to ZIP with metadata
                    url = try QRExportManager.exportAsZIP(qrCodes: qrCodes, batchName: qrSetName)
                }
                
                await MainActor.run {
                    exportProgress = 1.0
                    isExporting = false
                    exportedURL = url
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
    
    private func shareFile(url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(activityVC, animated: true)
        }
    }
}

