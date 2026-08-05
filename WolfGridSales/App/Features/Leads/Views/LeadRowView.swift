import SwiftUI

/// Compact row for the Field Leads inbox list (~72pt height).
struct FieldLeadRowView: View {
    let lead: FieldLead
    var isSelectionMode = false
    var isSelected = false
    let onTap: () -> Void
    var onEnterSelectionMode: (() -> Void)?
    var onDelete: (() -> Void)?
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? .accent : .muted)
                }

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accent)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.displayNameOrUnknown)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    
                    Text(lead.listDisplayAddress)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(lead.relativeTimeDisplay)
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                        if !lead.noteOrQRPreview.isEmpty {
                            Text("•")
                                .foregroundColor(.muted)
                            Text(lead.noteOrQRPreview)
                                .font(.system(size: 13))
                                .foregroundColor(.muted)
                                .lineLimit(1)
                        }
                        if let crmLabel = lead.crmSyncStatusLabel {
                            Text("•")
                                .foregroundColor(.muted)
                            Text(crmLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(lead.syncStatus == .failed ? Color.red : Color.muted)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer(minLength: 8)
                
                if isSelectionMode {
                    Text(isSelected ? "Selected" : "Select")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .accent : .muted)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isSelectionMode, let onEnterSelectionMode {
                Button {
                    onEnterSelectionMode()
                } label: {
                    Label("Select Multiple", systemImage: "checklist")
                }
            }

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    List {
        FieldLeadRowView(
            lead: FieldLead(
                userId: UUID(),
                address: "147 Bastedo Ave",
                name: "Ryan Secrest",
                status: .notHome,
                notes: "Met wife",
                createdAt: Date().addingTimeInterval(-7200)
            ),
            onTap: {}
        )
        FieldLeadRowView(
            lead: FieldLead(
                userId: UUID(),
                address: "55 Huntingwood Dr",
                name: nil,
                status: .qrScanned,
                qrCode: "FLYR2024",
                createdAt: Date().addingTimeInterval(-14400)
            ),
            onTap: {}
        )
    }
    .listStyle(.plain)
}
