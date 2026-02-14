import SwiftUI

/// Modern QR Tab Home Screen with 3x2 tile grid (6 squares)
struct QRHomeView: View {
    @State private var showCreateQR = false
    @State private var showPrintQR = false
    @State private var showQRMap = false
    @State private var showAnalytics = false
    @State private var showQRCodesList = false
    
    let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Dynamic gradient background that adapts to color scheme
            LinearGradient(
                colors: colorScheme == .dark ? [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.08, blue: 0.12)
                ] : [
                    Color.bg,
                    Color.bgSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // 3x2 Tile Grid (6 squares)
                LazyVGrid(columns: columns, spacing: 20) {
                    // Create QR Code Tile
                    QRHomeTile(
                        title: "Create QR Code",
                        icon: "qrcode.viewfinder"
                    ) {
                        showCreateQR = true
                    }
                    
                    // Print QR Codes Tile
                    QRHomeTile(
                        title: "Print QR Codes",
                        icon: "printer"
                    ) {
                        showPrintQR = true
                    }
                    
                    // QR Map Tile
                    QRHomeTile(
                        title: "QR Map",
                        icon: "map"
                    ) {
                        showQRMap = true
                    }
                    
                    // Analytics Tile
                    QRHomeTile(
                        title: "Analytics",
                        icon: "chart.bar.fill"
                    ) {
                        showAnalytics = true
                    }
                    
                    // QR Code List Tile
                    QRHomeTile(
                        title: "QR Code List",
                        icon: "list.bullet"
                    ) {
                        showQRCodesList = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showCreateQR) {
            CreateQRView()
        }
        .navigationDestination(isPresented: $showPrintQR) {
            PrintQRView(qrCodeId: nil)
        }
        .navigationDestination(isPresented: $showQRMap) {
            QRCodeMapView()
        }
        .navigationDestination(isPresented: $showAnalytics) {
            QRCodeAnalyticsView()
        }
        .navigationDestination(isPresented: $showQRCodesList) {
            QRCodeManageView()
        }
    }
}

/// Individual tile component with glassy material and tap animation
struct QRHomeTile: View {
    let title: String
    let icon: String
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void
    
    init(title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(Color.text)
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
            }
            .shadow(color: colorScheme == .dark ? .black.opacity(0.15) : .black.opacity(0.1), radius: 12, y: 6)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        QRHomeView()
    }
}

