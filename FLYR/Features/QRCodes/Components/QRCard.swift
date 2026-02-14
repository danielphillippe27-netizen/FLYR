import SwiftUI
import UIKit

/// Apple-style QR code card component matching Campaign card design
struct QRCard: View {
    // MARK: - Data
    
    // Support both QRCode and QRCodeAddress models
    private let qrCode: QRCode?
    private let qrCodeAddress: QRCodeAddress?
    
    // Display properties
    private let qrName: String
    private let campaignName: String?
    private let qrUrl: String
    private let qrVariant: String?
    private let isLinked: Bool
    
    // MARK: - Callbacks
    
    let onLink: (() -> Void)?
    let onUnlink: (() -> Void)?
    let onPrint: (() -> Void)?
    let onAnalytics: (() -> Void)?
    let onDelete: (() -> Void)?
    let onTap: (() -> Void)?
    
    // MARK: - State
    
    @State private var qrImage: UIImage?
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Initializers
    
    /// Initialize with QRCode model
    init(
        qr: QRCode,
        campaignName: String? = nil,
        onLink: (() -> Void)? = nil,
        onUnlink: (() -> Void)? = nil,
        onPrint: (() -> Void)? = nil,
        onAnalytics: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.qrCode = qr
        self.qrCodeAddress = nil
        self.qrName = qr.metadata?.name ?? qr.metadata?.entityName ?? "QR Code"
        self.campaignName = campaignName
        self.qrUrl = qr.qrUrl
        self.qrVariant = qr.qrVariant
        self.isLinked = false
        self.onLink = onLink
        self.onUnlink = onUnlink
        self.onPrint = onPrint
        self.onAnalytics = onAnalytics
        self.onDelete = onDelete
        self.onTap = onTap
    }
    
    /// Initialize with QRCodeAddress model
    init(
        qr: QRCodeAddress,
        campaignName: String? = nil,
        onLink: (() -> Void)? = nil,
        onUnlink: (() -> Void)? = nil,
        onPrint: (() -> Void)? = nil,
        onAnalytics: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.qrCode = nil
        self.qrCodeAddress = qr
        self.qrName = qr.formatted
        self.campaignName = campaignName
        self.qrUrl = qr.webURL
        self.qrVariant = nil
        self.isLinked = false
        self.onLink = onLink
        self.onUnlink = onUnlink
        self.onPrint = onPrint
        self.onAnalytics = onAnalytics
        self.onDelete = onDelete
        self.onTap = onTap
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top Row: QR Preview + Info
            HStack(spacing: 16) {
                // QR Code Preview
                qrPreviewImage
                
                // Info Section
                VStack(alignment: .leading, spacing: 6) {
                    // QR Name
                    Text(qrName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    // Campaign Name
                    if let campaignName = campaignName {
                        Text(campaignName)
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                            .opacity(0.6)
                    }
                    
                    Spacer()
                }
                
                Spacer()
                
                // Badges (Top-right)
                VStack(alignment: .trailing, spacing: 8) {
                    if let variant = qrVariant {
                        VariantBadge(variant: variant)
                    }
                    
                    if isLinked {
                        LinkedBadge()
                    }
                }
            }
            
            // Bottom Row: Action Buttons (if any callbacks provided)
            if hasActions {
                actionButtons
            }
        }
        .padding(16)
        .background(backgroundView)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.1) {
            withAnimation {
                isPressed = true
            }
        } onPressingChanged: { pressing in
            withAnimation {
                isPressed = pressing
            }
            if pressing {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            loadQRImage()
        }
    }
    
    // MARK: - QR Preview Image
    
    private var qrPreviewImage: some View {
        Group {
            if let qrImage = qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 5)
            } else {
                ProgressView()
                    .frame(width: 80, height: 80)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var backgroundView: some View {
        if colorScheme == .dark {
            // Dark mode: Use campaign-style glass overlay
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.secondarySystemBackground).opacity(0.25))
        } else {
            // Light mode: White with opacity
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.9))
        }
    }
    
    // MARK: - Action Buttons
    
    private var hasActions: Bool {
        onLink != nil || onUnlink != nil || onPrint != nil || onAnalytics != nil || onDelete != nil
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let onLink = onLink, !isLinked {
                QRCardActionButton(title: "Link", icon: "link", action: onLink)
            }
            
            if let onUnlink = onUnlink, isLinked {
                QRCardActionButton(title: "Unlink", icon: "link.badge.minus", action: onUnlink, isDestructive: true)
            }
            
            if let onPrint = onPrint {
                QRCardActionButton(title: "Print", icon: "printer", action: onPrint)
            }
            
            if let onAnalytics = onAnalytics {
                QRCardActionButton(title: "Analytics", icon: "chart.bar", action: onAnalytics)
            }
            
            if let onDelete = onDelete {
                QRCardActionButton(title: "Delete", icon: "trash", action: onDelete, isDestructive: true)
            }
        }
    }
    
    // MARK: - QR Image Loading
    
    private func loadQRImage() {
        // Try to load from QRCode model first
        if let qrCode = qrCode {
            if let base64Image = qrCode.qrImage,
               let imageData = Data(base64Encoded: base64Image),
               let image = UIImage(data: imageData) {
                qrImage = image
                return
            }
        }
        
        // Try to load from QRCodeAddress model
        if let qrCodeAddress = qrCodeAddress,
           let imageData = qrCodeAddress.qrCodeImage,
           let image = UIImage(data: imageData) {
            qrImage = image
            return
        }
        
        // Generate QR code image from URL
        if let image = QRCodeGenerator.generate(from: qrUrl, size: CGSize(width: 200, height: 200)) {
            qrImage = image
        }
    }
}

// MARK: - Variant Badge

private struct VariantBadge: View {
    let variant: String
    
    var body: some View {
        Capsule()
            .fill(Color.red.opacity(0.22))
            .frame(height: 26)
            .overlay(
                Text("Variant \(variant)")
                    .font(.flyrCaption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
            )
    }
}

// MARK: - Linked Badge

private struct LinkedBadge: View {
    var body: some View {
        Capsule()
            .fill(Color.green.opacity(0.22))
            .frame(height: 26)
            .overlay(
                Text("Linked")
                    .font(.flyrCaption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
            )
    }
}

// MARK: - Action Button

private struct QRCardActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    let isDestructive: Bool
    
    init(title: String, icon: String, action: @escaping () -> Void, isDestructive: Bool = false) {
        self.title = title
        self.icon = icon
        self.action = action
        self.isDestructive = isDestructive
    }
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isDestructive ? Color.red : Color(hex: "FF4D4D"))
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        QRCard(
            qr: QRCode(
                id: UUID(),
                qrUrl: "https://flyrpro.app/address/test",
                metadata: QRCodeMetadata(
                    entityName: "Test Campaign",
                    name: "123 Main Street"
                )
            ),
            campaignName: "Summer Campaign",
            onPrint: {},
            onAnalytics: {}
        )
        .padding(.horizontal, 20)
        
        QRCard(
            qr: QRCode(
                id: UUID(),
                landingPageId: UUID(),
                qrVariant: "A",
                qrUrl: "https://flyrpro.app/address/test",
                metadata: QRCodeMetadata(
                    entityName: "Winter Campaign",
                    name: "456 Oak Avenue"
                )
            ),
            campaignName: "Winter Campaign",
            onUnlink: {},
            onPrint: {}
        )
        .padding(.horizontal, 20)
    }
    .padding()
    .background(Color.bg)
}

