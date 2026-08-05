import SwiftUI

/// Main QR Code Hub Screen
/// Orchestrates navigation only - no business logic
struct QRCodeHubView: View {
    @StateObject private var hook = UseQRCodeHub()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        QRHubSquare(
                            title: "Create QR Code",
                            icon: "qrcode",
                            color: .blue
                        ) {
                            hook.navigateTo(.create)
                        }
                        
                        QRHubSquare(
                            title: "Print QR Code",
                            icon: "printer.fill",
                            color: .green
                        ) {
                            hook.navigateTo(.print)
                        }
                        
                        QRHubSquare(
                            title: "Analytics",
                            icon: "chart.bar.fill",
                            color: .purple
                        ) {
                            hook.navigateTo(.analytics)
                        }
                        
                        QRHubSquare(
                            title: "QR Map",
                            icon: "map.fill",
                            color: .teal
                        ) {
                            hook.navigateTo(.mapView)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
            }
            .navigationTitle("QR Codes")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $hook.selectedDestination) { destination in
                switch destination {
                case .create:
                    QRCodeCreateView()
                case .print:
                    QRPrintViewV2()
                case .analytics:
                    QRCodeAnalyticsView()
                case .mapView:
                    QRCodeMapView()
                }
            }
        }
    }
}

