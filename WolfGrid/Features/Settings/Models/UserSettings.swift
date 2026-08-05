import Foundation

struct UserSettings: Codable, Equatable {
    let user_id: UUID
    var exclude_weekends: Bool
    var dark_mode: Bool
    var follow_up_boss_key: String?
    var member_since: String?
    let updated_at: String?
    let created_at: String?
    
    // Branding fields for landing pages
    var brand_color: String?
    var logo_url: String?
    var realtor_profile_card: Data? // JSONB stored as Data
    var default_cta_color: String?
    var font_style: String?
    var default_template_id: UUID?
    var default_website: String?
    
    enum CodingKeys: String, CodingKey {
        case user_id
        case exclude_weekends
        case dark_mode
        case follow_up_boss_key
        case member_since
        case updated_at
        case created_at
        case brand_color
        case logo_url
        case realtor_profile_card
        case default_cta_color
        case font_style
        case default_template_id
        case default_website
    }
    
    // Computed property for default template ID
    var defaultTemplateId: UUID? {
        return default_template_id
    }
    
    // Helper to format member since date
    var formattedMemberSince: String? {
        guard let memberSince = member_since else { return nil }
        // Parse ISO8601 date and format for display
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: memberSince) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return memberSince
    }
}

