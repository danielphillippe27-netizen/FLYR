import SwiftUI

/// Stateless QR code display card
struct QRCodeCard: View {
    let qrCode: QRCodeAddress
    let onTap: () -> Void
    
    @State private var qrImage: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .background(Color.white)
                        .cornerRadius(8)
                } else {
                    ProgressView()
                        .frame(width: 120, height: 120)
                }
                
                Text(qrCode.formatted)
                    .font(.flyrCaption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onAppear {
            generateQRImage()
        }
    }
    
    private func generateQRImage() {
        if let image = QRCodeGenerator.generate(from: qrCode.webURL) {
            qrImage = image
        }
    }
}

