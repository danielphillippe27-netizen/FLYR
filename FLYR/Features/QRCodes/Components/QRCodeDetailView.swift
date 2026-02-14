import SwiftUI

/// QR Code Detail Sheet
struct QRCodeDetailView: View {
    let qrCode: QRCodeAddress
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(radius: 8)
                    } else {
                        ProgressView()
                            .frame(width: 250, height: 250)
                    }
                    
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Address")
                                .font(.flyrHeadline)
                            Text(qrCode.formatted)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Links")
                                .font(.flyrHeadline)
                            LinkRow(title: "Web URL", url: qrCode.webURL)
                            LinkRow(title: "Deep Link", url: qrCode.deepLinkURL)
                        }
                    }
                    
                    Button(action: shareQRCode) {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                    
                    NavigationLink(destination: ThermalPrintView(
                        qrURL: qrCode.webURL,
                        address: qrCode.formatted,
                        campaignName: nil
                    )) {
                        Label("Print QR Label", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                }
                .padding()
            }
            .navigationTitle("QR Code")
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
            generateQRImage()
        }
    }
    
    private func generateQRImage() {
        if let image = QRCodeGenerator.generate(from: qrCode.webURL, size: CGSize(width: 500, height: 500)) {
            qrImage = image
        }
    }
    
    private func shareQRCode() {
        guard let qrImage = qrImage else { return }
        let activityVC = UIActivityViewController(activityItems: [qrImage, qrCode.webURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

struct LinkRow: View {
    let title: String
    let url: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(url)
                .font(.flyrCaption)
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}

