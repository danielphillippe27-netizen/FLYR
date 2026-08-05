import SwiftUI

struct TypeChips: View {
    @Binding var selected: CampaignType
    var options: [CampaignType] = CampaignType.allCases
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { type in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selected = type
                        }
                    } label: {
                        Text(type.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 18)
                            .background(selected == type ? Color.red : Color(.systemGray6))
                            .foregroundStyle(selected == type ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(selected == type ? Color.red : Color(.separator).opacity(0.55), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    @Previewable @State var selected = CampaignType.flyer
    return TypeChips(selected: $selected)
        .padding()
}
