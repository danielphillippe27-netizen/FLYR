import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LandingPageEditView: View {
    let landingPage: CampaignLandingPage
    let onUpdated: () -> Void
    
    @StateObject private var viewModel = LandingPageEditViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showVideoPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Hero Media") {
                    Picker("Hero Type", selection: $viewModel.heroType) {
                        Text("Image").tag(HeroType.image)
                        Text("Video").tag(HeroType.video)
                        Text("YouTube").tag(HeroType.youtube)
                    }
                    
                    // Show existing hero media preview
                    if let existingUrl = viewModel.existingHeroUrl, let url = URL(string: existingUrl) {
                        if viewModel.heroType == .image {
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
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if viewModel.heroType == .video {
                            HStack {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.accent)
                                Text("Current Video")
                                    .foregroundColor(.muted)
                                Spacer()
                            }
                            .padding()
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if viewModel.heroType == .youtube {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.accent)
                                Text("YouTube Video")
                                    .foregroundColor(.muted)
                                Spacer()
                            }
                            .padding()
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    // Image picker
                    if viewModel.heroType == .image {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            HStack {
                                if let heroImage = viewModel.heroImage {
                                    Image(uiImage: heroImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 40))
                                        .foregroundColor(.muted)
                                        .frame(width: 100, height: 100)
                                        .background(Color.bgSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                
                                Text(viewModel.heroImage == nil ? "Change Hero Image" : "Update Image")
                                    .foregroundColor(.accent)
                                
                                Spacer()
                            }
                        }
                        
                        if viewModel.heroImage != nil {
                            Button("Remove New Image", role: .destructive) {
                                viewModel.heroImage = nil
                                selectedPhoto = nil
                            }
                        }
                    }
                    
                    // Video file picker
                    if viewModel.heroType == .video {
                        Button {
                            showVideoPicker = true
                        } label: {
                            HStack {
                                if let videoUrl = viewModel.heroVideo {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.accent)
                                        .frame(width: 100, height: 100)
                                        .background(Color.bgSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Text(videoUrl.lastPathComponent)
                                        .foregroundColor(.accent)
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "video")
                                        .font(.system(size: 40))
                                        .foregroundColor(.muted)
                                        .frame(width: 100, height: 100)
                                        .background(Color.bgSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Text("Select New Video")
                                        .foregroundColor(.accent)
                                }
                                
                                Spacer()
                            }
                        }
                        
                        if viewModel.heroVideo != nil {
                            Button("Remove New Video", role: .destructive) {
                                viewModel.heroVideo = nil
                            }
                        }
                    }
                    
                    // YouTube URL input
                    if viewModel.heroType == .youtube {
                        TextField("YouTube URL", text: $viewModel.heroVideoUrl)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.heroVideoUrl) { _, newValue in
                                viewModel.youtubeUrlError = nil
                                if !newValue.isEmpty && !viewModel.isValidYouTubeURL(newValue) {
                                    viewModel.youtubeUrlError = "Please enter a valid YouTube URL"
                                }
                            }
                        
                        if let error = viewModel.youtubeUrlError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.error)
                        } else if !viewModel.heroVideoUrl.isEmpty {
                            Text("Examples: youtube.com/watch?v=..., youtu.be/...")
                                .font(.caption)
                                .foregroundColor(.muted)
                        }
                    }
                }
                
                Section("Content") {
                    TextField("Title", text: $viewModel.title)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Headline", text: $viewModel.headline)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Subheadline", text: $viewModel.subheadline)
                        .textInputAutocapitalization(.sentences)
                }
                
                Section("Call to Action") {
                    Picker("CTA Type", selection: $viewModel.ctaType) {
                        ForEach(viewModel.ctaTypes, id: \.self) { type in
                            Text(viewModel.ctaTypeDisplayName(for: type))
                                .tag(type)
                        }
                    }
                    
                    if viewModel.shouldShowCtaUrl {
                        TextField("CTA URL", text: $viewModel.ctaUrl)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } else {
                        Text("URL not needed for Form CTA")
                            .font(.caption)
                            .foregroundColor(.muted)
                    }
                }
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
                    Button("Save") {
                        Task {
                            do {
                                _ = try await viewModel.updateLandingPage()
                                // Haptic feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                onUpdated()
                                dismiss()
                            } catch {
                                // Error is handled by viewModel
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
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
            .onAppear {
                viewModel.loadLandingPage(landingPage)
            }
            .onChange(of: selectedPhoto) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.heroImage = image
                    }
                }
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
}


