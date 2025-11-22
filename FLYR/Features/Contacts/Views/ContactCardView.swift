import SwiftUI

struct ContactCardView: View {
    let contact: Contact
    let onTap: () -> Void
    let onLogActivity: () -> Void
    let onViewMap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Name + Tag
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.fullName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.text)
                            .lineLimit(1)
                        
                        // Tags
                        HStack(spacing: 8) {
                            if contact.campaignId != nil {
                                TagView(text: "Campaign", color: .error)
                            }
                            if contact.farmId != nil {
                                TagView(text: "Farm", color: .success)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Status badge
                    StatusBadge(status: contact.status)
                }
                
                // Address
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                    Text(contact.address)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.muted)
                        .lineLimit(2)
                }
                
                // Info row: Phone, Last Contacted, Notes preview
                VStack(alignment: .leading, spacing: 8) {
                    if let phone = contact.phone {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.muted)
                            Text(phone)
                                .font(.system(size: 13))
                                .foregroundColor(.muted)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.muted)
                        Text("Last: \(contact.lastContactedDisplay)")
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                    }
                    
                    if let notes = contact.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onLogActivity) {
                Label("Log Activity", systemImage: "plus.circle.fill")
            }
            .tint(.info)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash.fill")
            }
            
            Button(action: onViewMap) {
                Label("View on Map", systemImage: "map.fill")
            }
            .tint(.success)
        }
    }
}

// MARK: - Tag View

struct TagView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(8)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ContactStatus
    
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

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ContactCardView(
            contact: Contact.mockContacts[0],
            onTap: {},
            onLogActivity: {},
            onViewMap: {},
            onDelete: {}
        )
        
        ContactCardView(
            contact: Contact.mockContacts[1],
            onTap: {},
            onLogActivity: {},
            onViewMap: {},
            onDelete: {}
        )
    }
    .padding()
    .background(Color.bg)
}





