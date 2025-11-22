import SwiftUI
import PhotosUI

struct HeroMediaPicker: View {
    @Binding var heroType: String
    @Binding var heroImageURL: String?
    @Binding var youtubeURL: String?
    @Binding var youtubeThumbnailURL: String?
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var heroImage: UIImage?
    @State private var youtubeUrlInput: String = ""
    @State private var youtubeUrlError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hero Type Picker
            Picker("Hero Type", selection: $heroType) {
                Text("Image").tag("image")
                Text("YouTube Video").tag("youtube")
            }
            .pickerStyle(.segmented)
            
            // Image Picker
            if heroType == "image" {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        if let image = heroImage {
                            Image(uiImage: image)
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
                        
                        Text(heroImage == nil ? "Select Hero Image" : "Change Image")
                            .foregroundColor(.accent)
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                if heroImage != nil {
                    Button("Remove Image", role: .destructive) {
                        heroImage = nil
                        selectedPhoto = nil
                        heroImageURL = nil
                    }
                    .font(.system(size: 14))
                }
            }
            
            // YouTube URL Input
            if heroType == "youtube" {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("YouTube URL", text: $youtubeUrlInput)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: youtubeUrlInput) { _, newValue in
                            validateAndProcessYouTubeURL(newValue)
                        }
                    
                    if let error = youtubeUrlError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.error)
                    } else if !youtubeUrlInput.isEmpty && YouTubeHelper.isValidYouTubeURL(youtubeUrlInput) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.success)
                            Text("Valid YouTube URL")
                                .font(.system(size: 12))
                                .foregroundColor(.success)
                        }
                    } else if !youtubeUrlInput.isEmpty {
                        Text("Examples: youtube.com/watch?v=..., youtu.be/...")
                            .font(.system(size: 12))
                            .foregroundColor(.muted)
                    }
                    
                    // Thumbnail preview if available
                    if let thumbnailURL = youtubeThumbnailURL, let url = URL(string: thumbnailURL) {
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
                            // Play button overlay
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 8)
                        )
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    heroImage = image
                    // In real implementation, upload image and set heroImageURL
                }
            }
        }
        .onAppear {
            if heroType == "youtube", let url = youtubeURL {
                youtubeUrlInput = url
            }
        }
    }
    
    private func validateAndProcessYouTubeURL(_ urlString: String) {
        youtubeUrlError = nil
        
        guard !urlString.isEmpty else {
            youtubeURL = nil
            youtubeThumbnailURL = nil
            return
        }
        
        if YouTubeHelper.isValidYouTubeURL(urlString) {
            youtubeURL = urlString
            
            // Extract video ID and generate thumbnail URL
            if let videoId = YouTubeHelper.extractYouTubeId(from: urlString) {
                youtubeThumbnailURL = YouTubeHelper.youtubeThumbnailURL(videoId: videoId)
            }
        } else {
            youtubeUrlError = "Please enter a valid YouTube URL"
            youtubeURL = nil
            youtubeThumbnailURL = nil
        }
    }
}

#Preview {
    HeroMediaPicker(
        heroType: .constant("image"),
        heroImageURL: .constant(nil),
        youtubeURL: .constant(nil),
        youtubeThumbnailURL: .constant(nil)
    )
    .padding()
}


