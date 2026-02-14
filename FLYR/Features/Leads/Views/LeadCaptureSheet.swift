import SwiftUI
/// Shown when user taps a building during an active session: capture status + note, then Save to Leads or Just Mark.
struct LeadCaptureSheet: View {
    let addressDisplay: String
    let campaignId: UUID
    let sessionId: UUID?
    let gersIdString: String
    
    var onSave: (FieldLead) async -> Void
    var onJustMark: () async -> Void
    var onDismiss: () -> Void
    
    @State private var selectedStatus: FieldLeadStatus = .notHome
    @State private var quickNote: String = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(addressDisplay)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.text)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.muted)
                    HStack(spacing: 10) {
                        ForEach([FieldLeadStatus.notHome, .interested, .noAnswer], id: \.self) { status in
                            Button {
                                selectedStatus = status
                            } label: {
                                Text(status.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(selectedStatus == status ? .white : .text)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(selectedStatus == status ? status.color : Color.gray.opacity(0.2))
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.muted)
                    TextField("Optional note…", text: $quickNote)
                        .textFieldStyle(.roundedBorder)
                        .padding(0)
                }
                
                Spacer(minLength: 24)
                
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await saveToLeads()
                        }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save to Leads")
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accent)
                        .cornerRadius(12)
                    }
                    .disabled(isSaving)
                    .buttonStyle(.plain)
                    
                    Button {
                        Task {
                            await onJustMark()
                            onDismiss()
                        }
                    } label: {
                        Text("Just Mark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .navigationTitle("Capture Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }
    
    private func saveToLeads() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        isSaving = true
        defer { isSaving = false }
        let lead = FieldLead(
            userId: userId,
            address: addressDisplay,
            name: nil,
            phone: nil,
            status: selectedStatus,
            notes: quickNote.isEmpty ? nil : quickNote,
            qrCode: nil,
            campaignId: campaignId,
            sessionId: sessionId
        )
        await onSave(lead)
        onDismiss()
    }
}

#Preview {
    LeadCaptureSheet(
        addressDisplay: "147 Bastedo Ave",
        campaignId: UUID(),
        sessionId: UUID(),
        gersIdString: "abc-123",
        onSave: { _ in },
        onJustMark: {},
        onDismiss: {}
    )
}
