import SwiftUI
import Combine

/// Editor view for landing pages with live preview
public struct LandingPageEditorView: View {
    @StateObject private var viewModel: LandingPageEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showImagePicker = false
    
    public init(pageData: LandingPageData) {
        _viewModel = StateObject(wrappedValue: LandingPageEditorViewModel(pageData: pageData))
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Template Picker Section
                    templatePickerSection
                    
                    // Content Editor Section
                    contentEditorSection
                    
                    // Live Preview Section
                    previewSection
                }
                .padding()
            }
            .navigationTitle("Edit Landing Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Publish") {
                        Task {
                            await viewModel.save()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task {
                await viewModel.loadTemplates()
            }
            .alert("Success", isPresented: $viewModel.showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Landing page saved successfully")
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    // MARK: - Template Picker
    
    private var templatePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Template")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(LandingPageTemplate.allCases) { template in
                    TemplateCard(
                        template: template,
                        isSelected: viewModel.selectedTemplate == template
                    ) {
                        viewModel.updateTemplate(template)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Content Editor
    
    private var contentEditorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Content")
                .font(.headline)
            
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Enter title", text: Binding(
                    get: { viewModel.pageData.title },
                    set: { viewModel.updateTitle($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // Subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text("Subtitle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Enter subtitle", text: Binding(
                    get: { viewModel.pageData.subtitle },
                    set: { viewModel.updateSubtitle($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { viewModel.pageData.description ?? "" },
                    set: { viewModel.updateDescription($0) }
                ))
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
            
            // CTA Text
            VStack(alignment: .leading, spacing: 4) {
                Text("CTA Text")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Button text", text: Binding(
                    get: { viewModel.pageData.ctaText },
                    set: { viewModel.updateCTAText($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // CTA URL
            VStack(alignment: .leading, spacing: 4) {
                Text("CTA URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("https://...", text: Binding(
                    get: { viewModel.pageData.ctaURL },
                    set: { viewModel.updateCTAURL($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
            }
            
            // Image URL
            VStack(alignment: .leading, spacing: 4) {
                Text("Hero Image URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("https://...", text: Binding(
                    get: { viewModel.pageData.imageURL ?? "" },
                    set: { viewModel.updateImageURL($0.isEmpty ? nil : $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Preview
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Preview")
                .font(.headline)
            
            LandingPageEditorPreview(
                pageData: $viewModel.pageData,
                branding: nil
            )
            .frame(height: 600)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

/// Template card for picker
struct TemplateCard: View {
    let template: LandingPageTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(template.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

