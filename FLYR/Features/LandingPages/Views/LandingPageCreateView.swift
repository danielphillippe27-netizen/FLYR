import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LandingPageCreateView: View {
    let campaignId: UUID
    let campaignName: String
    let onCreated: () -> Void
    
    @StateObject private var viewModel = LandingPageCreateViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showVideoPicker = false
    @State private var slug: String = ""
    
    // Collapsible section states
    @State private var isContentExpanded = true
    @State private var isHeroExpanded = true
    @State private var isThemeExpanded = true
    @State private var isWallpaperExpanded = false
    @State private var isTextExpanded = false
    @State private var isButtonsExpanded = false
    @State private var isColorsExpanded = false
    @State private var isCTAExpanded = false
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isCompact {
                    compactLayout
                } else {
                    sideBySideLayout
                }
            }
            .navigationTitle("Create Landing Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            do {
                                _ = try await viewModel.createLandingPage(
                                    campaignId: campaignId,
                                    campaignName: campaignName
                                )
                                onCreated()
                                dismiss()
                            } catch {
                                // Error is handled by viewModel
                            }
                        }
                    }
                    .disabled(viewModel.isCreating)
                }
            }
            .fileImporter(
                isPresented: $showVideoPicker,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .avi],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        _ = url.startAccessingSecurityScopedResource()
                        viewModel.heroVideo = url
                    }
                case .failure(let error):
                    print("Error selecting video: \(error)")
                }
            }
            .onChange(of: selectedPhoto) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.heroImage = image
                    }
                }
            }
            .onAppear {
                slug = CampaignLandingPage.generateSlug(from: campaignName)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
        }
    }
    
    // MARK: - Compact Layout (Mobile)
    
    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preview at top on mobile
                previewSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                Divider()
                
                // Settings panels
                VStack(spacing: 16) {
                    campaignSection
                        .padding(.horizontal, 16)
                    
                    allSections
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Side-by-Side Layout (iPad/Desktop)
    
    private var sideBySideLayout: some View {
        HStack(spacing: 0) {
            // LEFT SIDE - Settings Panels
            ScrollView {
                VStack(spacing: 16) {
                    campaignSection
                    allSections
                }
                .padding(16)
            }
            .frame(width: 400)
            .background(Color.bg)
            
            Divider()
            
            // RIGHT SIDE - Live Preview
            previewSection
                .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        ZStack {
            Color.bgSecondary
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                DesignerPreview(
                    metadata: $viewModel.metadata,
                    title: viewModel.title.isEmpty ? "Your Title" : viewModel.title,
                    headline: viewModel.headline.isEmpty ? "Your Headline" : viewModel.headline,
                    subheadline: viewModel.subheadline.isEmpty ? "Your subheadline text" : viewModel.subheadline,
                    ctaText: viewModel.ctaTypeDisplayName(for: viewModel.ctaType)
                )
                
                Spacer()
            }
        }
    }
    
    // MARK: - All Sections
    
    private var allSections: some View {
        VStack(spacing: 16) {
            collapsibleSection(
                title: "Content",
                isExpanded: $isContentExpanded
            ) {
                contentSection
            }
            
            collapsibleSection(
                title: "Hero Media",
                isExpanded: $isHeroExpanded
            ) {
                heroMediaSection
            }
            
            collapsibleSection(
                title: "Theme",
                isExpanded: $isThemeExpanded
            ) {
                ThemePicker(selectedTheme: $viewModel.metadata.themeStyle)
                    .onChange(of: viewModel.metadata.themeStyle) { _, newTheme in
                        if let theme = LandingPageTheme.allCases.first(where: { $0.rawValue == newTheme }) {
                            viewModel.metadata = theme.toMetadata()
                        }
                    }
            }
            
            collapsibleSection(
                title: "Wallpaper",
                isExpanded: $isWallpaperExpanded
            ) {
                WallpaperPicker(
                    wallpaperStyle: $viewModel.metadata.wallpaperStyle,
                    wallpaperColor: $viewModel.metadata.wallpaperColor,
                    wallpaperImageURL: $viewModel.metadata.wallpaperImageURL,
                    wallpaperVideoURL: $viewModel.metadata.wallpaperVideoURL
                )
            }
            
            collapsibleSection(
                title: "Text",
                isExpanded: $isTextExpanded
            ) {
                FontPicker(
                    titleFont: $viewModel.metadata.titleFont,
                    bodyFont: $viewModel.metadata.bodyFont,
                    titleSize: $viewModel.metadata.titleSize
                )
            }
            
            collapsibleSection(
                title: "Buttons",
                isExpanded: $isButtonsExpanded
            ) {
                ButtonStylePicker(
                    buttonStyle: $viewModel.metadata.buttonStyle,
                    buttonCornerRadius: $viewModel.metadata.buttonCornerRadius
                )
            }
            
            collapsibleSection(
                title: "Colors",
                isExpanded: $isColorsExpanded
            ) {
                DesignerColorPicker(
                    wallpaperColor: $viewModel.metadata.wallpaperColor,
                    titleColor: $viewModel.metadata.titleColor,
                    pageTextColor: $viewModel.metadata.pageTextColor,
                    buttonColor: $viewModel.metadata.buttonBackgroundColor,
                    buttonTextColor: $viewModel.metadata.buttonTextColor
                )
            }
            
            collapsibleSection(
                title: "Call to Action",
                isExpanded: $isCTAExpanded
            ) {
                ctaSection
            }
        }
    }
    
    // MARK: - Campaign Section
    
    private var campaignSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Campaign")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            Text(campaignName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $viewModel.title)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            HStack {
                TextField("Slug", text: $slug)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Button("Generate") {
                    slug = CampaignLandingPage.generateSlug(from: viewModel.title.isEmpty ? campaignName : viewModel.title)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            TextField("Headline", text: $viewModel.headline)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            TextField("Subheadline", text: $viewModel.subheadline)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Hero Media Section
    
    private var heroMediaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Hero Type", selection: Binding(
                get: { viewModel.heroType == .youtube ? HeroType.youtube : HeroType.image },
                set: { 
                    viewModel.heroType = $0
                    viewModel.metadata.heroType = $0 == .youtube ? "youtube" : "image"
                }
            )) {
                Text("Image").tag(HeroType.image)
                Text("YouTube").tag(HeroType.youtube)
            }
            .pickerStyle(.segmented)
            
            if viewModel.heroType == .image {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        if let heroImage = viewModel.heroImage {
                            Image(uiImage: heroImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.muted)
                                .frame(width: 100, height: 100)
                                .background(Color.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Text(viewModel.heroImage == nil ? "Select Hero Image" : "Change Image")
                            .foregroundColor(.accent)
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                if viewModel.heroImage != nil {
                    Button("Remove Image", role: .destructive) {
                        viewModel.heroImage = nil
                        selectedPhoto = nil
                        viewModel.metadata.heroImageURL = nil
                    }
                    .font(.system(size: 14))
                }
            } else if viewModel.heroType == .youtube {
                TextField("YouTube URL", text: $viewModel.heroVideoUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: viewModel.heroVideoUrl) { _, newValue in
                        viewModel.youtubeUrlError = nil
                        if !newValue.isEmpty && !viewModel.isValidYouTubeURL(newValue) {
                            viewModel.youtubeUrlError = "Please enter a valid YouTube URL"
                        } else if !newValue.isEmpty {
                            viewModel.metadata.youtubeURL = newValue
                            if let videoId = YouTubeHelper.extractYouTubeId(from: newValue) {
                                viewModel.metadata.youtubeThumbnailURL = YouTubeHelper.youtubeThumbnailURL(videoId: videoId)
                            }
                        }
                    }
                
                if let error = viewModel.youtubeUrlError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.error)
                } else if !viewModel.heroVideoUrl.isEmpty && YouTubeHelper.isValidYouTubeURL(viewModel.heroVideoUrl) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.success)
                        Text("Valid YouTube URL")
                            .font(.system(size: 12))
                            .foregroundColor(.success)
                    }
                }
                
                if let thumbnailURL = viewModel.metadata.youtubeThumbnailURL, let url = URL(string: thumbnailURL) {
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
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 8)
                    )
                }
            }
        }
    }
    
    // MARK: - CTA Section
    
    private var ctaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("CTA Type", selection: $viewModel.ctaType) {
                ForEach(viewModel.ctaTypes, id: \.self) { type in
                    Text(viewModel.ctaTypeDisplayName(for: type))
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .padding(12)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if viewModel.shouldShowCtaUrl {
                TextField("CTA URL", text: $viewModel.ctaUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("URL not needed for Form CTA")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Collapsible Section Helper
    
    private func collapsibleSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.wrappedValue.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.muted)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.bgSecondary)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}
