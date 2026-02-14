import SwiftUI

/// Compact row for the Field Leads inbox list (~72pt height).
struct FieldLeadRowView: View {
    let lead: FieldLead
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accent)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.address)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(lead.displayNameOrUnknown)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.text)
                        Text("•")
                            .foregroundColor(.muted)
                        FieldLeadStatusBadge(status: lead.status)
                    }
                    
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
                    }
                }
                
                Spacer(minLength: 8)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

struct FieldLeadStatusBadge: View {
    let status: FieldLeadStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color)
            .cornerRadius(8)
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
