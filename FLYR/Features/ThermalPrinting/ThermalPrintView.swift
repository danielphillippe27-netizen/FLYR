import SwiftUI
import UIKit

/// SwiftUI view for thermal label printing interface
public struct ThermalPrintView: View {
    let qrURL: String
    let address: String?
    let campaignName: String?
    
    private let printManager = ThermalPrintManager.shared
    @State private var selectedSize: ThermalLabelSize = .size2x2
    @State private var generatedURL: URL?
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var shareSheetItems: [Any] = []
    
    @Environment(\.dismiss) private var dismiss
    
    public init(qrURL: String, address: String?, campaignName: String?) {
        self.qrURL = qrURL
        self.address = address
        self.campaignName = campaignName
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Size Picker
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Label Size")
                                .font(.headline)
                            
                            Picker("Label Size", selection: $selectedSize) {
                                Text(ThermalLabelSize.size2x2.displayName)
                                    .tag(ThermalLabelSize.size2x2)
                                Text(ThermalLabelSize.size3x3.displayName)
                                    .tag(ThermalLabelSize.size3x3)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedSize) { _ in
                                // Reset generated label when size changes
                                generatedURL = nil
                                generatedImage = nil
                            }
                        }
                    }
                    
                    // Preview
                    if let generatedImage = generatedImage {
                        Card {
                            VStack(spacing: 12) {
                                Text("Preview")
                                    .font(.headline)
                                
                                Image(uiImage: generatedImage)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(maxWidth: 300, maxHeight: 300)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .shadow(radius: 4)
                                
                                Text("\(Int(selectedSize.pixelSize.width))×\(Int(selectedSize.pixelSize.height)) px @ \(selectedSize.dpi) DPI")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if isGenerating {
                        Card {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Generating label...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    
                    // Generate Button
                    Button(action: generateLabel) {
                        Label("Generate Label", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                    .disabled(isGenerating)
                    
                    // Print Button (only shown when label is generated)
                    if generatedURL != nil {
                        VStack(spacing: 12) {
                            Button(action: printViaAirPrint) {
                                Label("Print via AirPrint", systemImage: "printer")
                                    .frame(maxWidth: .infinity)
                            }
                            .primaryButton()
                            
                            Button(action: printViaShareSheet) {
                                Label("Print via Share Sheet", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryButton()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Print QR Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
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
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: shareSheetItems)
            }
        }
    }
    
    private func generateLabel() {
        isGenerating = true
        errorMessage = nil
        generatedURL = nil
        generatedImage = nil
        
        Task {
            do {
                let url = try await printManager.generateLabel(
                    qrURL: qrURL,
                    address: address,
                    campaign: campaignName,
                    size: selectedSize
                )
                
                // Load the image for preview
                if let imageData = try? Data(contentsOf: url),
                   let image = UIImage(data: imageData) {
                    await MainActor.run {
                        generatedURL = url
                        generatedImage = image
                        isGenerating = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to load generated label"
                        isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate label: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }
    
    private func printViaAirPrint() {
        guard let url = generatedURL else { return }
        printManager.airPrint(url: url)
    }
    
    private func printViaShareSheet() {
        guard let url = generatedURL else { return }
        shareSheetItems = [url]
        showShareSheet = true
    }
}

/// SwiftUI wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

