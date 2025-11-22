import SwiftUI

/// Reusable form row button with consistent styling
public struct FormRowButton: View {
    let title: String
    let value: String?
    let placeholder: String
    let action: () -> Void
    
    public init(
        title: String,
        value: String?,
        placeholder: String = "Select",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.placeholder = placeholder
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack {
                Text(value ?? placeholder)
                    .font(.system(size: 16))
                    .foregroundColor(value != nil ? .primary : .secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}


