import SwiftUI

struct SourceSegment: View {
    @Binding var selected: AddressSource
    
    var body: some View {
        HStack(spacing: 4) {
            segment("Nearby", .closestHome)
            segment("Map", .map)
        }
        .padding(4)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder 
    private func segment(_ title: String, _ value: AddressSource) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { 
                selected = value 
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .foregroundStyle(selected == value ? .red : .white)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selected = AddressSource.closestHome
    return SourceSegment(selected: $selected)
        .padding()
}
