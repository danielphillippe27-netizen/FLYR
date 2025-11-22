import SwiftUI

/// Stateless address filter component for analytics
struct AddressFilter: View {
    let addresses: [AddressRow]
    let selectedId: UUID?
    let onSelectAll: () -> Void
    let onSelectAddress: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filter by Address")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button {
                        onSelectAll()
                    } label: {
                        Text("All Addresses")
                            .font(.subheadline)
                            .foregroundStyle(selectedId == nil ? .white : .primary)
                            .padding()
                            .background(selectedId == nil ? Color.accent : Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(addresses) { address in
                        Button {
                            onSelectAddress(address.id)
                        } label: {
                            Text(address.formatted)
                                .font(.caption)
                                .foregroundStyle(selectedId == address.id ? .white : .primary)
                                .padding()
                                .background(selectedId == address.id ? Color.accent : Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

