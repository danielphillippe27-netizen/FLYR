import SwiftUI
struct LeadDetailView: View {
    let lead: FieldLead
    var onConnectCRM: () -> Void
    var onDismiss: (() -> Void)?
    
    @State private var integrations: [UserIntegration] = []
    @State private var showSyncSettings = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    private var connectedProvider: IntegrationProvider? {
        integrations.first { $0.isConnected }?.provider
    }
    
    private var lastSyncedText: String? {
        guard let at = lead.lastSyncedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: at, relativeTo: Date())
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                addressSection
                fieldNotesSection
                if lead.qrCode != nil { qrSection }
                syncSection
                actionsSection
            }
            .padding(20)
        }
        .navigationTitle(lead.address)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIntegrations() }
        .sheet(isPresented: $showSyncSettings) {
            SyncSettingsView()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
    }
    
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Address", systemImage: "mappin.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text(lead.address)
                .font(.system(size: 16))
                .foregroundColor(.text)
            Button("Open in Maps") {
                let encoded = lead.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.accent)
        }
    }
    
    private var fieldNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Field Notes")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.text)
            Divider().background(Color.border)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                        .foregroundColor(.muted)
                    Text(lead.status.displayName)
                        .foregroundColor(.text)
                }
                .font(.system(size: 15))
                Text("Last: \(lead.createdAt, style: .date) at \(lead.createdAt, style: .time)")
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                if let sessionId = lead.sessionId {
                    Text("Captured during Session")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                }
                if let notes = lead.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 15))
                        .foregroundColor(.text)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("QR Scan", systemImage: "qrcode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text(lead.qrCode ?? "")
                .font(.system(size: 15))
                .foregroundColor(.text)
        }
    }
    
    private var syncSection: some View {
        Group {
            if let provider = connectedProvider {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Synced to \(provider.displayName)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.text)
                    }
                    if let t = lastSyncedText {
                        Text("Last sync: \(t)")
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                    }
                    Button("View in \(provider.displayName) →") {
                        // Phase 1: no deep link
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pro Tip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.text)
                    Text("Connect FUB to auto-sync this lead to your office.")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)
                    Button("Connect CRM →") {
                        showSyncSettings = true
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button(action: shareLead) {
                Label("Share Lead", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            Button(action: exportLead) {
                Label("Export", systemImage: "doc.text")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func loadIntegrations() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        do {
            integrations = try await CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
        } catch {}
    }
    
    private func shareLead() {
        shareItems = [LeadsExportManager.shareableText(for: lead)]
        showShareSheet = true
    }
    
    private func exportLead() {
        do {
            let url = try LeadsExportManager.exportToTempFile(leads: [lead], filename: "lead_\(lead.id.uuidString.prefix(8)).csv")
            shareItems = [url]
            showShareSheet = true
        } catch {}
    }
}

#Preview {
    NavigationStack {
        LeadDetailView(
            lead: FieldLead(
                userId: UUID(),
                address: "147 Bastedo Ave, Toronto, ON",
                name: "Ryan Secrest",
                status: .notHome,
                notes: "Met wife, call back at 6pm. Left flyer on door.",
                sessionId: UUID()
            ),
            onConnectCRM: {}
        )
    }
}
