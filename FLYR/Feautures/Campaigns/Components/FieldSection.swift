import SwiftUI

/// A section container with header and content
struct FieldSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(title)
                .font(.subheading)
                .foregroundColor(.text)
            
            // Content
            content
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        FieldSection(title: "Campaign Basics") {
            VStack(spacing: 12) {
                TextField("Campaign name", text: .constant("Sample Campaign"))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        
        FieldSection(title: "Address Source") {
            Text("Address configuration options would go here")
                .foregroundColor(.muted)
        }
    }
    .padding()
}
