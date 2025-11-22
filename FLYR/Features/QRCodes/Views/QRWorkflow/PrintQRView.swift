import SwiftUI
import UniformTypeIdentifiers
import Combine

/// View for printing and exporting QR codes
struct PrintQRView: View {
    let qrCodeId: UUID?
    
    @StateObject private var viewModel = PrintQRViewModel()
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    init(qrCodeId: UUID?) {
        self.qrCodeId = qrCodeId
    }
    
    var body: some View {
        ZStack {
            Color.bgSecondary.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
            } else if let qrCode = viewModel.qrCode,
                      let qrImageData = qrCode.qrImage,
                      let imageData = Data(base64Encoded: qrImageData),
                      let uiImage = UIImage(data: imageData) {
                ScrollView {
                    VStack(spacing: 24) {
                        // QR Code Preview
                        Card {
                            VStack(spacing: 16) {
                                Text("QR Code Preview")
                                    .font(.headline)
                                    .foregroundColor(.text)
                                
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .cornerRadius(8)
                                
                                if let address = viewModel.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(.muted)
                                } else if let slug = qrCode.slug {
                                    Text("Slug: \(slug)")
                                        .font(.caption)
                                        .foregroundColor(.muted)
                                }
                            }
                        }
                        
                        // Export Options
                        exportOptionsSection
                        
                        // Share Button
                        shareButton
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 48))
                        .foregroundColor(.muted)
                    
                    Text("QR Code Not Found")
                        .font(.headline)
                        .foregroundColor(.text)
                }
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showShareSheet) {
            QRShareSheet(activityItems: shareItems)
        }
        .task {
            if let qrCodeId = qrCodeId {
                await viewModel.loadQRCode(id: qrCodeId)
            }
        }
        .onChange(of: viewModel.qrCode) { _, newValue in
            if let addressId = newValue?.addressId {
                Task {
                    await viewModel.loadAddress(addressId: addressId)
                }
            }
        }
    }
    
    private var exportOptionsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Options")
                    .font(.headline)
                    .foregroundColor(.text)
                
                VStack(spacing: 12) {
                    exportButton(title: "Export as PNG", icon: "photo") {
                        await exportPNG()
                    }
                    
                    exportButton(title: "Export as SVG", icon: "doc.text") {
                        await exportSVG()
                    }
                    
                    exportButton(title: "Export as PDF (8.5x11)", icon: "doc.fill") {
                        await exportPDF()
                    }
                    
                    Divider()
                    
                    exportButton(title: "Thermal Label 2x2", icon: "printer.fill") {
                        await exportThermal(size: .size2x2)
                    }
                    
                    exportButton(title: "Thermal Label 3x3", icon: "printer.fill") {
                        await exportThermal(size: .size3x3)
                    }
                    
                    Divider()
                    
                    exportButton(title: "Canva Export", icon: "square.and.arrow.down") {
                        await exportCanva()
                    }
                }
            }
        }
    }
    
    private func exportButton(title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentDefault)
                Text(title)
                    .foregroundColor(.text)
                Spacer()
            }
            .padding()
            .background(Color.bgSecondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var shareButton: some View {
        Button {
            Task {
                await shareQRCode()
            }
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share QR Code")
            }
            .frame(maxWidth: .infinity)
        }
        .primaryButton()
    }
    
    private func exportPNG() async {
        guard let qrCode = viewModel.qrCode,
              let qrImageData = qrCode.qrImage,
              let imageData = Data(base64Encoded: qrImageData),
              let uiImage = UIImage(data: imageData) else { return }
        
        // Use existing PNG export service if available
        if let pngData = uiImage.pngData() {
            await MainActor.run {
                shareItems = [pngData]
                showShareSheet = true
            }
        }
    }
    
    private func exportSVG() async {
        // SVG export would need to be implemented
        await MainActor.run {
            viewModel.error = "SVG export coming soon"
        }
    }
    
    private func exportPDF() async {
        guard let qrCode = viewModel.qrCode,
              let qrImageData = qrCode.qrImage,
              let imageData = Data(base64Encoded: qrImageData),
              let uiImage = UIImage(data: imageData) else { return }
        
        // Use existing PDF export service if available
        // For now, create a simple PDF
        let pdfData = createSimplePDF(image: uiImage)
        await MainActor.run {
            shareItems = [pdfData]
            showShareSheet = true
        }
    }
    
    private func exportThermal(size: ThermalLabelSize) async {
        // Thermal printing would use existing thermal printing service
        await MainActor.run {
            viewModel.error = "Thermal printing coming soon"
        }
    }
    
    private func exportCanva() async {
        guard let qrCode = viewModel.qrCode,
              let qrImageData = qrCode.qrImage,
              let imageData = Data(base64Encoded: qrImageData),
              let uiImage = UIImage(data: imageData) else { return }
        
        // Export as PNG for Canva (Canva can import PNG images)
        if let pngData = uiImage.pngData() {
            await MainActor.run {
                shareItems = [uiImage, pngData]
                showShareSheet = true
            }
        }
    }
    
    private func shareQRCode() async {
        guard let qrCode = viewModel.qrCode,
              let qrImageData = qrCode.qrImage,
              let imageData = Data(base64Encoded: qrImageData),
              let uiImage = UIImage(data: imageData) else { return }
        
        await MainActor.run {
            shareItems = [uiImage, qrCode.qrUrl]
            showShareSheet = true
        }
    }
    
    private func createSimplePDF(image: UIImage) -> Data {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)) // 8.5x11 inches at 72 DPI
        return pdfRenderer.pdfData { context in
            context.beginPage()
            let imageRect = CGRect(x: 206, y: 296, width: 200, height: 200) // Center on page
            image.draw(in: imageRect)
        }
    }
}

struct QRShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = controller.popoverPresentationController {
            // This will be set by the presenting view controller
            popover.permittedArrowDirections = [.up, .down]
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

@MainActor
class PrintQRViewModel: ObservableObject {
    @Published var qrCode: QRCode?
    @Published var address: String?
    @Published var isLoading = false
    @Published var error: String?
    
    private let qrRepository = QRRepository.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    func loadQRCode(id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            qrCode = try await qrRepository.fetchQRCode(id: id)
            // Load address if QR code has an addressId
            if let addressId = qrCode?.addressId {
                await loadAddress(addressId: addressId)
            }
        } catch {
            self.error = "Failed to load QR code: \(error.localizedDescription)"
        }
    }
    
    func loadAddress(addressId: UUID) async {
        do {
            if let addressRow = try await campaignsAPI.fetchAddress(addressId: addressId) {
                address = addressRow.formatted
            }
        } catch {
            print("⚠️ [PrintQR] Failed to load address: \(error.localizedDescription)")
            // Don't set error here, just log it - address is optional
        }
    }
}

