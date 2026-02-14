import SwiftUI

private let nudgeDismissedKey = "flyr_leads_sync_nudge_dismissed"

/// Soft nudge card to connect CRM; dismissible, persisted in UserDefaults.
struct CRMConnectCard: View {
    var onConnect: () -> Void
    var onDismiss: () -> Void
    
    @AppStorage(nudgeDismissedKey) private var nudgeDismissed = false
    
    var body: some View {
        if nudgeDismissed { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect FUB")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.text)
                        Text("Auto-sync leads to your CRM")
                            .font(.system(size: 14))
                            .foregroundColor(.muted)
                    }
                    Spacer()
                    Button(action: {
                        nudgeDismissed = true
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.muted)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 12) {
                    Button(action: onConnect) {
                        Text("Connect – 30 sec")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accent)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(16)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        )
    }
}

#Preview {
    VStack {
        CRMConnectCard(onConnect: {}, onDismiss: {})
    }
    .padding()
}
