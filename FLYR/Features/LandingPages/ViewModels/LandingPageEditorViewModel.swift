import SwiftUI
import Combine

/// View model for landing page editor
@MainActor
final class LandingPageEditorViewModel: ObservableObject {
    @Published var pageData: LandingPageData
    @Published var selectedTemplate: LandingPageTemplate
    @Published var availableTemplates: [LandingPageTemplateDB] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var showSuccess = false
    
    private let landingPagesAPI = LandingPagesAPI.shared
    private let brandingService = BrandingService.shared
    
    init(pageData: LandingPageData) {
        self.pageData = pageData
        self.selectedTemplate = pageData.template
    }
    
    /// Load available templates
    func loadTemplates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            availableTemplates = try await landingPagesAPI.fetchTemplates()
        } catch {
            errorMessage = "Failed to load templates: \(error.localizedDescription)"
            print("❌ Error loading templates: \(error)")
        }
    }
    
    /// Update title
    func updateTitle(_ title: String) {
        pageData = LandingPageData(
            id: pageData.id,
            userId: pageData.userId,
            campaignId: pageData.campaignId,
            addressId: pageData.addressId,
            templateId: pageData.templateId,
            title: title,
            subtitle: pageData.subtitle,
            description: pageData.description,
            ctaText: pageData.ctaText,
            ctaURL: pageData.ctaURL,
            imageURL: pageData.imageURL,
            videoURL: pageData.videoURL,
            dynamicData: pageData.dynamicData,
            slug: pageData.slug,
            createdAt: pageData.createdAt,
            updatedAt: pageData.updatedAt,
            name: pageData.name,
            url: pageData.url,
            type: pageData.type
        )
    }
    
    /// Update subtitle
    func updateSubtitle(_ subtitle: String) {
        pageData = LandingPageData(
            id: pageData.id,
            userId: pageData.userId,
            campaignId: pageData.campaignId,
            addressId: pageData.addressId,
            templateId: pageData.templateId,
            title: pageData.title,
            subtitle: subtitle,
            description: pageData.description,
            ctaText: pageData.ctaText,
            ctaURL: pageData.ctaURL,
            imageURL: pageData.imageURL,
            videoURL: pageData.videoURL,
            dynamicData: pageData.dynamicData,
            slug: pageData.slug,
            createdAt: pageData.createdAt,
            updatedAt: pageData.updatedAt,
            name: pageData.name,
            url: pageData.url,
            type: pageData.type
        )
    }
    
    /// Update description
    func updateDescription(_ description: String) {
        pageData = LandingPageData(
            id: pageData.id,
            userId: pageData.userId,
            campaignId: pageData.campaignId,
            addressId: pageData.addressId,
            templateId: pageData.templateId,
            title: pageData.title,
            subtitle: pageData.subtitle,
            description: description.isEmpty ? nil : description,
            ctaText: pageData.ctaText,
            ctaURL: pageData.ctaURL,
            imageURL: pageData.imageURL,
            videoURL: pageData.videoURL,
            dynamicData: pageData.dynamicData,
            slug: pageData.slug,
            createdAt: pageData.createdAt,
            updatedAt: pageData.updatedAt,
            name: pageData.name,
            url: pageData.url,
            type: pageData.type
        )
    }
    
    /// Update CTA text
    func updateCTAText(_ text: String) {
        pageData = LandingPageData(
            id: pageData.id,
            userId: pageData.userId,
            campaignId: pageData.campaignId,
            addressId: pageData.addressId,
            templateId: pageData.templateId,
            title: pageData.title,
            subtitle: pageData.subtitle,
            description: pageData.description,
            ctaText: text,
            ctaURL: pageData.ctaURL,
            imageURL: pageData.imageURL,
            videoURL: pageData.videoURL,
            dynamicData: pageData.dynamicData,
            slug: pageData.slug,
            createdAt: pageData.createdAt,
            updatedAt: pageData.updatedAt,
            name: pageData.name,
            url: pageData.url,
            type: pageData.type
        )
    }
    
    /// Update CTA URL
    func updateCTAURL(_ url: String) {
        pageData = LandingPageData(
            id: pageData.id,
            userId: pageData.userId,
            campaignId: pageData.campaignId,
            addressId: pageData.addressId,
            templateId: pageData.templateId,
            title: pageData.title,
            subtitle: pageData.subtitle,
            description: pageData.description,
            ctaText: pageData.ctaText,
            ctaURL: url,
            imageURL: pageData.imageURL,
            videoURL: pageData.videoURL,
            dynamicData: pageData.dynamicData,
            slug: pageData.slug,
            createdAt: pageData.createdAt,
            updatedAt: pageData.updatedAt,
            name: pageData.name,
            url: pageData.url,
            type: pageData.type
        )
    }
    
    /// Update image URL
    func updateImageURL(_ url: String?) {
        pageData = LandingPageData(
            id: pageData.id,
            userId: pageData.userId,
            campaignId: pageData.campaignId,
            addressId: pageData.addressId,
            templateId: pageData.templateId,
            title: pageData.title,
            subtitle: pageData.subtitle,
            description: pageData.description,
            ctaText: pageData.ctaText,
            ctaURL: pageData.ctaURL,
            imageURL: url,
            videoURL: pageData.videoURL,
            dynamicData: pageData.dynamicData,
            slug: pageData.slug,
            createdAt: pageData.createdAt,
            updatedAt: pageData.updatedAt,
            name: pageData.name,
            url: pageData.url,
            type: pageData.type
        )
    }
    
    /// Update template
    func updateTemplate(_ template: LandingPageTemplate) {
        selectedTemplate = template
        // Find template ID from available templates
        if let templateDB = availableTemplates.first(where: { $0.name == template.displayName }) {
            pageData = LandingPageData(
                id: pageData.id,
                userId: pageData.userId,
                campaignId: pageData.campaignId,
                addressId: pageData.addressId,
                templateId: templateDB.id,
                title: pageData.title,
                subtitle: pageData.subtitle,
                description: pageData.description,
                ctaText: pageData.ctaText,
                ctaURL: pageData.ctaURL,
                imageURL: pageData.imageURL,
                videoURL: pageData.videoURL,
                dynamicData: pageData.dynamicData,
                slug: pageData.slug,
                createdAt: pageData.createdAt,
                updatedAt: pageData.updatedAt,
                name: pageData.name,
                url: pageData.url,
                type: pageData.type
            )
        }
    }
    
    /// Save landing page
    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            let updatePayload = LandingPageUpdatePayload(
                title: pageData.title,
                subtitle: pageData.subtitle,
                description: pageData.description,
                ctaText: pageData.ctaText,
                ctaURL: pageData.ctaURL,
                imageURL: pageData.imageURL,
                videoURL: pageData.videoURL,
                templateId: pageData.templateId
            )
            
            _ = try await landingPagesAPI.updateLandingPage(id: pageData.id, data: updatePayload)
            showSuccess = true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ Error saving landing page: \(error)")
        }
    }
}

