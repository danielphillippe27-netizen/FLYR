import SwiftUI

/// Compact, theme-aware contact row for the Field Leads inbox.
struct FieldLeadRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var avatarSize = 36
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

                avatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.displayNameOrUnknown)
                        .font(.system(.body, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)

                    Text(lead.listDisplayAddress)
                        .font(.subheadline)
                        .foregroundColor(.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(lead.relativeTimeDisplay)
                    .font(.caption)
                    .foregroundColor(.muted)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

    private var initials: String {
        let parts = (lead.name ?? "").split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first else { return "" }
        let lastInitial = parts.count > 1 ? String(parts.last?.prefix(1) ?? "") : ""
        return (String(first.prefix(1)) + lastInitial).uppercased()
    }

    private var avatar: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(.subheadline, weight: .medium))
            } else {
                Text(initials)
                    .font(.system(.subheadline, weight: .semibold))
            }
        }
        .foregroundColor(Color(white: colorScheme == .dark ? 0.84 : 0.28))
        .frame(width: avatarSize, height: avatarSize)
        .background(Color(white: colorScheme == .dark ? 0.16 : 0.94), in: Circle())
        .accessibilityHidden(true)
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
