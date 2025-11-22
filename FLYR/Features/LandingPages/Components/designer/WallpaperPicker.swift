import SwiftUI
import PhotosUI

struct WallpaperPicker: View {
    @Binding var wallpaperStyle: String
    @Binding var wallpaperColor: String?
    @Binding var wallpaperImageURL: String?
    @Binding var wallpaperVideoURL: String?
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var colorPickerColor: Color = .white
    
    let wallpaperStyles = ["Fill", "Gradient", "Blur", "Pattern", "Image", "Video"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Style picker
            Picker("Wallpaper Style", selection: $wallpaperStyle) {
                ForEach(wallpaperStyles, id: \.self) { style in
                    Text(style).tag(style)
                }
            }
            .pickerStyle(.segmented)
            
            // Style-specific controls
            Group {
                switch wallpaperStyle {
                case "Fill":
                    colorPickerSection
                case "Gradient":
                    gradientSection
                case "Blur":
                    blurSection
                case "Pattern":
                    patternSection
                case "Image":
                    imagePickerSection
                case "Video":
                    videoPickerSection
                default:
                    EmptyView()
                }
            }
        }
        .onChange(of: selectedPhoto) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    // In real implementation, upload image and set wallpaperImageURL
                }
            }
        }
        .onChange(of: colorPickerColor) { _, newColor in
            wallpaperColor = hexString(from: newColor)
        }
        .onAppear {
            if let colorHex = wallpaperColor {
                colorPickerColor = Color(hex: colorHex)
            }
        }
    }
    
    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            ColorPicker("Wallpaper Color", selection: $colorPickerColor, supportsOpacity: false)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var gradientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gradient")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            Text("Gradient editor coming soon")
                .font(.system(size: 14))
                .foregroundColor(.muted)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var blurSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blur Effect")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            Text("Frosted glass blur background")
                .font(.system(size: 14))
                .foregroundColor(.muted)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pattern")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            Text("Grid pattern background")
                .font(.system(size: 14))
                .foregroundColor(.muted)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var imagePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.muted)
                            .frame(width: 60, height: 60)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Text(selectedImage == nil ? "Select Image" : "Change Image")
                        .foregroundColor(.accent)
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var videoPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
            
            Text("Video wallpaper coming soon")
                .font(.system(size: 14))
                .foregroundColor(.muted)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    WallpaperPicker(
        wallpaperStyle: .constant("Fill"),
        wallpaperColor: .constant(nil),
        wallpaperImageURL: .constant(nil),
        wallpaperVideoURL: .constant(nil)
    )
    .padding()
}

