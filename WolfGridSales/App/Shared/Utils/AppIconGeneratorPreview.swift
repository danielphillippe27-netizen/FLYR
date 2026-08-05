import SwiftUI

/// Preview view for the app icon generator
struct AppIconGeneratorPreview: View {
    @State private var iconImage: UIImage?
    
    var body: some View {
        VStack(spacing: 20) {
            if let iconImage = iconImage {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                
                Button("Save Icon to AppIcon.appiconset") {
                    saveIcon()
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                Text("Generating icon...")
            }
        }
        .padding()
        .onAppear {
            generateIcon()
        }
    }
    
    private func generateIcon() {
        iconImage = AppIconGenerator.generate()
    }
    
    private func saveIcon() {
        guard iconImage != nil else { return }
        
        // Get the AppIcon.appiconset directory
        guard let bundlePath = Bundle.main.resourcePath else { return }
        let assetsPath = (bundlePath as NSString).deletingLastPathComponent
            .appending("/Assets.xcassets/AppIcon.appiconset")
        let outputURL = URL(fileURLWithPath: assetsPath)
        
        do {
            try AppIconGenerator.saveIcon(to: outputURL)
            
            // Show success alert
            if let presenter = ShareCardGenerator.rootViewController() {
                let alert = UIAlertController(
                    title: "Success",
                    message: "Icon saved to AppIcon.appiconset",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                presenter.present(alert, animated: true)
            }
        } catch {
            print("Failed to save icon: \(error)")
        }
    }
}

#Preview {
    AppIconGeneratorPreview()
}
