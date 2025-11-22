import SwiftUI

/// Bottom sheet with additional QR tools in Settings-style list
struct MoreToolsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showQRCodesList = false
    @State private var showLandingPagePreview = false
    @State private var showQRMap = false
    @State private var showExportAnalytics = false
    @State private var showEdgeFunctionDebug = false
    
    var body: some View {
        NavigationStack {
            List {
                // QR Codes List
                MoreToolsRow(
                    title: "QR Codes List",
                    icon: "list.bullet",
                    action: {
                        showQRCodesList = true
                    }
                )
                
                // Landing Page Preview
                MoreToolsRow(
                    title: "Landing Page Preview",
                    icon: "eye",
                    action: {
                        showLandingPagePreview = true
                    }
                )
                
                // QR Map
                MoreToolsRow(
                    title: "QR Map",
                    icon: "map",
                    action: {
                        showQRMap = true
                    }
                )
                
                // Export Analytics
                MoreToolsRow(
                    title: "Export Analytics",
                    icon: "chart.line.uptrend.xyaxis",
                    action: {
                        showExportAnalytics = true
                    }
                )
                
                // Edge Function Debug
                MoreToolsRow(
                    title: "Edge Function Debug",
                    icon: "ladybug",
                    action: {
                        showEdgeFunctionDebug = true
                    }
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showQRCodesList) {
                QRCodeManageView()
            }
            .navigationDestination(isPresented: $showLandingPagePreview) {
                LandingPageMainView()
            }
            .navigationDestination(isPresented: $showQRMap) {
                QRCodeMapView()
            }
            .navigationDestination(isPresented: $showExportAnalytics) {
                QRCodeAnalyticsView()
            }
            .navigationDestination(isPresented: $showEdgeFunctionDebug) {
                // Placeholder for Edge Function Debug view
                Text("Edge Function Debug")
                    .navigationTitle("Edge Function Debug")
            }
        }
    }
}

/// Settings-style row with leading icon and trailing chevron
struct MoreToolsRow: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.accentDefault)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.text)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.muted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    MoreToolsSheet()
}


