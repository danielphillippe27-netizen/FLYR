import SwiftUI

/// Live preview component for landing page designer
/// Shows iPhone-style mockup with real-time updates from metadata
struct DesignerPreview: View {
    @Binding var metadata: LandingPageMetadata
    let title: String
    let headline: String
    let subheadline: String
    let ctaText: String
    
    var body: some View {
        ZStack {
            // iPhone mockup background
            Color.bg
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // iPhone notch area
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 44)
                    .overlay(
                        HStack {
                            Text("9:41")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "signal")
                                Image(systemName: "wifi")
                                Image(systemName: "battery.100")
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                    )
                
                // Preview content
                ZStack {
                    // Wallpaper
                    wallpaperView
                    
                    // Content overlay
                    ScrollView {
                        VStack(spacing: 24) {
                            // Hero section
                            heroSection
                                .padding(.top, 20)
                            
                            // Text content
                            VStack(spacing: 16) {
                                if !title.isEmpty {
                                    Text(title)
                                        .font(titleFont)
                                        .foregroundColor(titleColor)
                                        .multilineTextAlignment(.center)
                                }
                                
                                if !headline.isEmpty {
                                    Text(headline)
                                        .font(headlineFont)
                                        .foregroundColor(textColor)
                                        .multilineTextAlignment(.center)
                                }
                                
                                if !subheadline.isEmpty {
                                    Text(subheadline)
                                        .font(bodyFont)
                                        .foregroundColor(textColor)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // CTA Button
                            if !ctaText.isEmpty {
                                ctaButton
                                    .padding(.horizontal, 24)
                            }
                            
                            Spacer(minLength: 40)
                        }
                    }
                }
            }
            .frame(width: 375, height: 812) // iPhone 13 Pro dimensions
            .background(
                RoundedRectangle(cornerRadius: 45)
                    .fill(Color.black)
                    .padding(8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 45)
                    .stroke(Color.black.opacity(0.2), lineWidth: 2)
                    .padding(8)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        }
    }
    
    // MARK: - Wallpaper View
    
    @ViewBuilder
    private var wallpaperView: some View {
        switch metadata.wallpaperStyle {
        case "Fill":
            if let colorHex = metadata.wallpaperColor {
                Color(hex: colorHex)
                    .ignoresSafeArea()
            } else {
                Color.bg
                    .ignoresSafeArea()
            }
            
        case "Gradient":
            LinearGradient(
                colors: [
                    Color(hex: metadata.wallpaperColor ?? "#FFFFFF"),
                    Color(hex: metadata.wallpaperTintColor ?? "#F5F5F7")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
        case "Blur":
            ZStack {
                if let colorHex = metadata.wallpaperColor {
                    Color(hex: colorHex)
                        .ignoresSafeArea()
                }
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
            
        case "Pattern":
            ZStack {
                if let colorHex = metadata.wallpaperColor {
                    Color(hex: colorHex)
                        .ignoresSafeArea()
                }
                // Grid pattern
                GeometryReader { geometry in
                    Path { path in
                        let spacing: CGFloat = 20
                        for x in stride(from: 0, to: geometry.size.width, by: spacing) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                        for y in stride(from: 0, to: geometry.size.height, by: spacing) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
            
        case "Image":
            if let imageURL = metadata.wallpaperImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.bgSecondary
                }
                .ignoresSafeArea()
            } else {
                Color.bg
                    .ignoresSafeArea()
            }
            
        case "Video":
            if let videoURL = metadata.wallpaperVideoURL {
                // Video wallpaper placeholder
                Color.bg
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "video.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.muted)
                    }
            } else {
                Color.bg
                    .ignoresSafeArea()
            }
            
        default:
            Color.bg
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Hero Section
    
    @ViewBuilder
    private var heroSection: some View {
        if metadata.heroType == "image" {
            if let imageURL = metadata.heroImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.bgSecondary)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 24)
            } else {
                Rectangle()
                    .fill(Color.bgSecondary.opacity(0.5))
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.muted)
                    }
                    .padding(.horizontal, 24)
            }
        } else if metadata.heroType == "youtube" {
            if let thumbnailURL = metadata.youtubeThumbnailURL, let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.bgSecondary)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    // Play button overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 12)
                }
                .padding(.horizontal, 24)
            } else {
                Rectangle()
                    .fill(Color.bgSecondary.opacity(0.5))
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        Image(systemName: "play.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.muted)
                    }
                    .padding(.horizontal, 24)
            }
        }
    }
    
    // MARK: - CTA Button
    
    @ViewBuilder
    private var ctaButton: some View {
        Button(action: {}) {
            Text(ctaText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(buttonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(buttonBackground)
                .clipShape(RoundedRectangle(cornerRadius: metadata.buttonCornerRadius))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var buttonBackground: some View {
        switch metadata.buttonStyle {
        case "Solid":
            if let colorHex = metadata.buttonBackgroundColor {
                Color(hex: colorHex)
            } else {
                Color.accent
            }
            
        case "Glass":
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                if let colorHex = metadata.buttonBackgroundColor {
                    Color(hex: colorHex)
                        .opacity(0.3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: metadata.buttonCornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            
        case "Outline":
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: metadata.buttonCornerRadius)
                        .stroke(buttonTextColor, lineWidth: 2)
                )
            
        default:
            Color.accent
        }
    }
    
    // MARK: - Font Helpers
    
    private var titleFont: Font {
        let size: CGFloat = metadata.titleSize == "Small" ? 24 : 32
        return fontForName(metadata.titleFont, size: size, weight: .bold)
    }
    
    private var headlineFont: Font {
        return fontForName(metadata.titleFont, size: 20, weight: .semibold)
    }
    
    private var bodyFont: Font {
        return fontForName(metadata.bodyFont, size: 16, weight: .regular)
    }
    
    private func fontForName(_ fontName: String, size: CGFloat, weight: Font.Weight) -> Font {
        switch fontName {
        case "SF Pro":
            return .system(size: size, weight: weight, design: .default)
        case "Rounded":
            return .system(size: size, weight: weight, design: .rounded)
        case "Calistoga":
            return .custom("Calistoga-Regular", size: size)
        case "Inter":
            return .custom("Inter-Regular", size: size)
        case "Poppins":
            return .custom("Poppins-Regular", size: size)
        case "Serif Pro":
            return .system(size: size, weight: weight, design: .serif)
        default:
            return .system(size: size, weight: weight, design: .default)
        }
    }
    
    // MARK: - Color Helpers
    
    private var titleColor: Color {
        if let hex = metadata.titleColor {
            return Color(hex: hex)
        }
        return .text
    }
    
    private var textColor: Color {
        if let hex = metadata.pageTextColor {
            return Color(hex: hex)
        }
        return .muted
    }
    
    private var buttonTextColor: Color {
        if let hex = metadata.buttonTextColor {
            return Color(hex: hex)
        }
        return .white
    }
}

#Preview {
    DesignerPreview(
        metadata: .constant(LandingPageMetadata()),
        title: "Welcome",
        headline: "Your Headline Here",
        subheadline: "Your subheadline text goes here",
        ctaText: "Get Started"
    )
}


