import SwiftUI

/// Modal view for selecting export mode
struct ExportModalView: View {
    let campaignId: UUID
    let batchName: String
    let addresses: [QRCodeAddress]
    let onDismiss: () -> Void
    
    @StateObject private var exportHook = UseExport()
    @State private var selectedMode: ExportMode?
    @State private var uploadToSupabase = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if exportHook.isExporting {
                    // Export in progress
                    VStack(spacing: 24) {
                        ProgressView(value: exportHook.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        
                        Text(exportHook.isUploading ? "Uploading to Supabase..." : "Exporting...")
                            .font(.flyrHeadline)
                            .foregroundStyle(.secondary)
                        
                        Text("\(Int(exportHook.progress * 100))%")
                            .font(.flyrTitle2)
                            .fontWeight(.semibold)
                    }
                    .padding()
                } else if exportHook.exportResult != nil {
                    // Export complete - show success view
                    ExportSuccessView(
                        exportResult: exportHook.exportResult!,
                        onDone: {
                            exportHook.clear()
                            dismiss()
                            onDismiss()
                        }
                    )
                } else {
                    // Export mode selection
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header
                            VStack(spacing: 8) {
                                Text("Export QR Codes")
                                    .font(.system(size: 28, weight: .bold))
                                
                                Text("Choose an export format")
                                    .font(.flyrSubheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                            
                            // Export options
                            VStack(spacing: 12) {
                                ForEach(ExportMode.allCases) { mode in
                                    ExportModeButton(
                                        mode: mode,
                                        isSelected: selectedMode == mode,
                                        onSelect: {
                                            selectedMode = mode
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                            
                            // Supabase upload toggle
                            Toggle("Upload to Supabase", isOn: $uploadToSupabase)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            
                            // Export button
                            Button {
                                guard let mode = selectedMode else { return }
                                Task {
                                    await exportHook.export(
                                        campaignId: campaignId,
                                        batchName: batchName,
                                        addresses: addresses,
                                        mode: mode,
                                        uploadToSupabase: uploadToSupabase
                                    )
                                }
                            } label: {
                                Text("Export")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(selectedMode != nil ? Color.red : Color(.systemGray4))
                                    .cornerRadius(12)
                            }
                            .disabled(selectedMode == nil || exportHook.isExporting)
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        exportHook.cancelExport()
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { exportHook.errorMessage != nil },
                set: { if !$0 { exportHook.errorMessage = nil } }
            )) {
                Button("OK") {
                    exportHook.errorMessage = nil
                }
            } message: {
                if let error = exportHook.errorMessage {
                    Text(error)
                }
            }
        }
    }
}

/// Button for selecting an export mode
private struct ExportModeButton: View {
    let mode: ExportMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: mode.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .white : .red)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.red.opacity(0.2) : Color(.systemGray6))
                    .cornerRadius(12)
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(mode.description)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.red.opacity(0.1) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

