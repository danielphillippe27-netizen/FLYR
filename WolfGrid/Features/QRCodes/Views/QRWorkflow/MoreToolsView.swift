import SwiftUI

/// View for additional QR workflow tools
struct MoreToolsView: View {
    var body: some View {
        ZStack {
            Color.bgSecondary.ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    toolCard(
                        title: "Bulk QR Generator",
                        description: "Generate multiple QR codes at once",
                        icon: "square.stack.3d.up.fill",
                        color: .green
                    ) {
                        // Placeholder for future implementation
                    }
                    
                    toolCard(
                        title: "Print Shop Export Manager",
                        description: "Export QR codes for professional printing",
                        icon: "printer.filled.and.paper",
                        color: .flyrPrimary
                    ) {
                        // Placeholder for future implementation
                    }
                    
                    toolCard(
                        title: "Analytics Real-Time Viewer",
                        description: "Monitor QR code scans and engagement in real-time",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .purple
                    ) {
                        // Placeholder for future implementation
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func toolCard(
        title: String,
        description: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Card {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(color)
                        .frame(width: 50, height: 50)
                        .background(color.opacity(0.1))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.flyrHeadline)
                            .foregroundColor(.text)
                        
                        Text(description)
                            .font(.flyrSubheadline)
                            .foregroundColor(.muted)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.flyrCaption)
                        .foregroundColor(.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}


