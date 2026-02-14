import SwiftUI

/// Stateless address selector component
struct AddressSelector: View {
    let addresses: [AddressRow]
    let selectedId: UUID?
    let isLoading: Bool
    let onSelect: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Address")
                .font(.flyrHeadline)
                .padding(.horizontal)
            
            if isLoading {
                ProgressView()
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(addresses) { address in
                            Button {
                                onSelect(address.id)
                            } label: {
                                Text(address.formatted)
                                    .font(.flyrSubheadline)
                                    .foregroundStyle(selectedId == address.id ? .white : .primary)
                                    .padding()
                                    .background(selectedId == address.id ? Color.accentColor : Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

