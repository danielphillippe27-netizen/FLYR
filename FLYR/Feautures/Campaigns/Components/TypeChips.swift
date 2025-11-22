import SwiftUI

struct TypeChips: View {
    @Binding var selected: CampaignType
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(CampaignType.allCases) { type in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { 
                        selected = type 
                    }
                } label: {
                    Text(type.title)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(selected == type ? Color.accentColor : Color(.systemGray6))
                        .foregroundStyle(selected == type ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    @Previewable @State var selected = CampaignType.flyer
    return TypeChips(selected: $selected)
        .padding()
}
