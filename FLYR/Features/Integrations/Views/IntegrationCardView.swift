import SwiftUI

/// Card view for displaying a CRM integration with connect/disconnect functionality
struct IntegrationCardView: View {
    let provider: IntegrationProvider
    let integration: UserIntegration?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    
    @State private var isConnecting = false
    
    private var isConnected: Bool {
        integration?.isConnected ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Logo + Name + Description + Button
            HStack(alignment: .center, spacing: 14) {
                // CRM Logo
                Image(provider.logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .padding(.leading, 4)
                
                // Name and Description
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline)
                        .foregroundColor(.text)
                    
                    Text(provider.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Connect/Disconnect Button
                Button(action: {
                    if isConnected {
                        onDisconnect()
                    } else {
                        onConnect()
                    }
                }) {
                    Text(isConnected ? "Disconnect" : "Connect")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isConnected ? .error : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isConnected ? Color.error.opacity(0.1) : Color.info)
                        )
                }
                .disabled(isConnecting)
            }
            
            // Connection status (if connected)
            if isConnected {
                Divider()
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.success)
                    
                    Text(integration?.connectionStatusText ?? "Connected")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                    
                    if provider.connectionType == .oauth, let expiresAt = integration?.expiresAt, integration?.isTokenExpired != true {
                        Text("•")
                            .foregroundColor(.muted)
                        Text("Expires \(formatExpirationDate(expiresAt))")
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func formatExpirationDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        IntegrationCardView(
            provider: .hubspot,
            integration: UserIntegration(
                userId: UUID(),
                provider: .hubspot,
                accessToken: "token123",
                expiresAt: Int(Date().addingTimeInterval(86400).timeIntervalSince1970)
            ),
            onConnect: {},
            onDisconnect: {}
        )
        
        IntegrationCardView(
            provider: .fub,
            integration: nil,
            onConnect: {},
            onDisconnect: {}
        )
    }
    .padding()
    .background(Color.bg)
}

