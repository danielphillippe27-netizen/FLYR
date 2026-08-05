import SwiftUI

/// Stateless campaign selector component
struct CampaignSelector: View {
    let campaigns: [CampaignListItem]
    let selectedId: UUID?
    let onSelect: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Campaign")
                .font(.flyrHeadline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(campaigns) { campaign in
                        Button {
                            onSelect(campaign.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(campaign.name)
                                    .font(.flyrHeadline)
                                    .foregroundStyle(selectedId == campaign.id ? .white : .primary)
                                
                                if let count = campaign.addressCount {
                                    Text("\(count) addresses")
                                        .font(.flyrCaption)
                                        .foregroundStyle(selectedId == campaign.id ? .white.opacity(0.8) : .secondary)
                                }
                            }
                            .frame(width: 150)
                            .padding()
                            .background(selectedId == campaign.id ? Color.accentColor : Color(.systemGray6))
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

