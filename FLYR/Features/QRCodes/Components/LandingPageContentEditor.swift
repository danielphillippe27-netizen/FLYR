import SwiftUI

/// Stateless landing page content editor component
struct LandingPageContentEditor: View {
    let content: AddressContent
    let isSaving: Bool
    let onSave: (AddressContent) -> Void
    
    @State private var title: String
    
    init(content: AddressContent, isSaving: Bool, onSave: @escaping (AddressContent) -> Void) {
        self.content = content
        self.isSaving = isSaving
        self.onSave = onSave
        _title = State(initialValue: content.title)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Title")
                            .font(.headline)
                        
                        TextField("Landing page title", text: $title)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Text("Videos: \(content.videos.count)")
                            Text("Images: \(content.images.count)")
                            Text("Forms: \(content.forms.count)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                
                Button {
                    let updated = AddressContent(
                        id: content.id,
                        addressId: content.addressId,
                        title: title,
                        videos: content.videos,
                        images: content.images,
                        forms: content.forms,
                        updatedAt: Date(),
                        createdAt: content.createdAt
                    )
                    onSave(updated)
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                    }
                }
                .primaryButton()
                .padding(.horizontal)
                .disabled(isSaving)
            }
            .padding(.vertical)
        }
    }
}

