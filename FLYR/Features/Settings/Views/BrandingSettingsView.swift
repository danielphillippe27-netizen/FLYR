import SwiftUI
import Combine
import Supabase

/// Branding settings view for landing pages
public struct BrandingSettingsView: View {
    @StateObject private var viewModel = BrandingSettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Brand Color
                Section("Brand Color") {
                    ColorPicker("Brand Color", selection: Binding(
                        get: { viewModel.brandColor },
                        set: { viewModel.brandColor = $0 }
                    ))
                }
                
                // Logo
                Section("Logo") {
                    TextField("Logo URL", text: Binding(
                        get: { viewModel.logoURL ?? "" },
                        set: { viewModel.logoURL = $0.isEmpty ? nil : $0 }
                    ))
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                }
                
                // CTA Color
                Section("Default CTA Color") {
                    ColorPicker("CTA Color", selection: Binding(
                        get: { viewModel.ctaColor },
                        set: { viewModel.ctaColor = $0 }
                    ))
                }
                
                // Font Style
                Section("Font Style") {
                    Picker("Font Style", selection: $viewModel.fontStyle) {
                        Text("System").tag("system")
                        Text("Serif").tag("serif")
                        Text("Sans-Serif").tag("sans-serif")
                    }
                }
                
                // Realtor Profile
                Section("Realtor Profile") {
                    TextField("Name", text: $viewModel.profileName)
                    TextField("Company", text: $viewModel.profileCompany)
                    TextField("Phone", text: $viewModel.profilePhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $viewModel.profileEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Photo URL", text: $viewModel.profilePhotoURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Branding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.save()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task {
                await viewModel.loadBranding()
            }
            .alert("Success", isPresented: $viewModel.showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Branding saved successfully")
            }
        }
    }
}

/// View model for branding settings
@MainActor
final class BrandingSettingsViewModel: ObservableObject {
    @Published var brandColor = Color.blue
    @Published var ctaColor = Color.red
    @Published var logoURL: String?
    @Published var fontStyle = "system"
    @Published var profileName = ""
    @Published var profileCompany = ""
    @Published var profilePhone = ""
    @Published var profileEmail = ""
    @Published var profilePhotoURL = ""
    @Published var isSaving = false
    @Published var showSuccess = false
    
    private let brandingService = BrandingService.shared
    
    func loadBranding() async {
        // Get user ID from Supabase session
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id
            
            if let branding = try await brandingService.fetchBranding(userId: userId) {
                if let hex = branding.brandColor {
                    brandColor = Color(hex: hex) ?? Color.blue
                }
                if let hex = branding.defaultCTAColor {
                    ctaColor = Color(hex: hex) ?? Color.red
                }
                logoURL = branding.logoURL
                fontStyle = branding.fontStyle ?? "system"
                
                if let profile = branding.realtorProfileCard {
                    profileName = profile.name ?? ""
                    profileCompany = profile.company ?? ""
                    profilePhone = profile.phone ?? ""
                    profileEmail = profile.email ?? ""
                    profilePhotoURL = profile.photoURL ?? ""
                }
            }
        } catch {
            print("❌ Error loading branding: \(error)")
        }
    }
    
    func save() async {
        // Get user ID from Supabase session
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            let profileCard = RealtorProfileCard(
                name: profileName.isEmpty ? nil : profileName,
                photoURL: profilePhotoURL.isEmpty ? nil : profilePhotoURL,
                phone: profilePhone.isEmpty ? nil : profilePhone,
                email: profileEmail.isEmpty ? nil : profileEmail,
                company: profileCompany.isEmpty ? nil : profileCompany,
                license: nil
            )
            
            let branding = LandingPageBranding(
                brandColor: hexString(from: brandColor),
                logoURL: logoURL,
                realtorProfileCard: profileCard,
                defaultCTAColor: hexString(from: ctaColor),
                fontStyle: fontStyle,
                defaultTemplateId: nil
            )
            
            try await brandingService.updateBranding(userId: userId, branding: branding)
            showSuccess = true
        } catch {
            print("❌ Error saving branding: \(error)")
        }
    }
    
    private func hexString(from color: Color) -> String {
        // Convert SwiftUI Color to hex string
        // This is a simplified version - in production you'd want a more robust conversion
        return "#000000" // Placeholder
    }
}

