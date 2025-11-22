import SwiftUI

/// A generic segmented picker for CaseIterable enums
struct SegmentedPicker<SelectionValue: CaseIterable & Hashable & Identifiable>: View {
    @Binding var selection: SelectionValue
    let title: String?
    
    init(selection: Binding<SelectionValue>, title: String? = nil) {
        self._selection = selection
        self.title = title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.label)
                    .foregroundColor(.text)
            }
            
            Picker(title ?? "Selection", selection: $selection) {
                ForEach(Array(SelectionValue.allCases), id: \.id) { option in
                    Text(optionLabel(for: option))
                        .tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
    
    private func optionLabel(for option: SelectionValue) -> String {
        // Try to get label from protocol if available
        if let labeled = option as? any LabeledEnum {
            return labeled.label
        }
        
        // Fallback to string representation
        return String(describing: option)
    }
}

// MARK: - Labeled Enum Protocol

protocol LabeledEnum {
    var label: String { get }
}

// MARK: - Extensions for our enums

extension CampaignType: LabeledEnum {}
extension AddressSource: LabeledEnum {}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SegmentedPicker(
            selection: .constant(CampaignType.flyer),
            title: "Campaign Type"
        )
        
        SegmentedPicker(
            selection: .constant(AddressSource.closestHome),
            title: "Address Source"
        )
    }
    .padding()
}
