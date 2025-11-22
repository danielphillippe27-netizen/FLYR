import Foundation

/// Metadata model for landing page designer configuration
/// Stores all theme, wallpaper, font, button, and color customization settings
public struct LandingPageMetadata: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    
    // MARK: - Theme
    /// Theme style: "Air", "Astrid", "Aura", "Breeze", "Grid", "Haven", "Lake", "Mineral", "Custom"
    public var themeStyle: String = "Air"
    
    // MARK: - Wallpaper
    /// Wallpaper style: "Fill", "Gradient", "Blur", "Pattern", "Image", "Video"
    public var wallpaperStyle: String = "Fill"
    /// Hex color string for wallpaper (Fill style)
    public var wallpaperColor: String?
    /// URL for wallpaper image (Image style)
    public var wallpaperImageURL: String?
    /// URL for wallpaper video (Video style)
    public var wallpaperVideoURL: String?
    
    // MARK: - Fonts
    /// Title font name: "SF Pro", "Rounded", "Calistoga", "Inter", "Poppins", "Serif Pro"
    public var titleFont: String = "SF Pro"
    /// Body font name
    public var bodyFont: String = "SF Pro"
    /// Title size: "Small" or "Large"
    public var titleSize: String = "Large"
    
    // MARK: - Buttons
    /// Button style: "Solid", "Glass", "Outline"
    public var buttonStyle: String = "Solid"
    /// Button corner radius (0-30)
    public var buttonCornerRadius: Double = 12.0
    /// Hex color string for button text
    public var buttonTextColor: String?
    /// Hex color string for button background
    public var buttonBackgroundColor: String?
    
    // MARK: - Global Colors
    /// Hex color string for title
    public var titleColor: String?
    /// Hex color string for page text
    public var pageTextColor: String?
    /// Hex color string for wallpaper tint
    public var wallpaperTintColor: String?
    
    // MARK: - Hero
    /// Hero type: "image", "youtube"
    public var heroType: String = "image"
    /// URL for hero image
    public var heroImageURL: String?
    /// YouTube video URL
    public var youtubeURL: String?
    /// YouTube thumbnail URL (auto-fetched)
    public var youtubeThumbnailURL: String?
    
    // MARK: - Version
    /// Metadata version for future migrations
    public var version: Int = 1
    
    public init(
        id: UUID = UUID(),
        themeStyle: String = "Air",
        wallpaperStyle: String = "Fill",
        wallpaperColor: String? = nil,
        wallpaperImageURL: String? = nil,
        wallpaperVideoURL: String? = nil,
        titleFont: String = "SF Pro",
        bodyFont: String = "SF Pro",
        titleSize: String = "Large",
        buttonStyle: String = "Solid",
        buttonCornerRadius: Double = 12.0,
        buttonTextColor: String? = nil,
        buttonBackgroundColor: String? = nil,
        titleColor: String? = nil,
        pageTextColor: String? = nil,
        wallpaperTintColor: String? = nil,
        heroType: String = "image",
        heroImageURL: String? = nil,
        youtubeURL: String? = nil,
        youtubeThumbnailURL: String? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.themeStyle = themeStyle
        self.wallpaperStyle = wallpaperStyle
        self.wallpaperColor = wallpaperColor
        self.wallpaperImageURL = wallpaperImageURL
        self.wallpaperVideoURL = wallpaperVideoURL
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.titleSize = titleSize
        self.buttonStyle = buttonStyle
        self.buttonCornerRadius = buttonCornerRadius
        self.buttonTextColor = buttonTextColor
        self.buttonBackgroundColor = buttonBackgroundColor
        self.titleColor = titleColor
        self.pageTextColor = pageTextColor
        self.wallpaperTintColor = wallpaperTintColor
        self.heroType = heroType
        self.heroImageURL = heroImageURL
        self.youtubeURL = youtubeURL
        self.youtubeThumbnailURL = youtubeThumbnailURL
        self.version = version
    }
}


