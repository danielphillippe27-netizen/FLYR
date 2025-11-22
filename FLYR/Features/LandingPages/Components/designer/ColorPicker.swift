import SwiftUI

struct DesignerColorPicker: View {
    @Binding var wallpaperColor: String?
    @Binding var titleColor: String?
    @Binding var pageTextColor: String?
    @Binding var buttonColor: String?
    @Binding var buttonTextColor: String?
    
    @State private var wallpaperColorValue: Color = .white
    @State private var titleColorValue: Color = .black
    @State private var pageTextColorValue: Color = .gray
    @State private var buttonColorValue: Color = .accent
    @State private var buttonTextColorValue: Color = .white
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Wallpaper Color
            colorRow(
                title: "Wallpaper",
                color: $wallpaperColorValue,
                hexBinding: $wallpaperColor
            )
            
            // Title Color
            colorRow(
                title: "Title",
                color: $titleColorValue,
                hexBinding: $titleColor
            )
            
            // Page Text Color
            colorRow(
                title: "Page Text",
                color: $pageTextColorValue,
                hexBinding: $pageTextColor
            )
            
            // Button Color
            colorRow(
                title: "Button",
                color: $buttonColorValue,
                hexBinding: $buttonColor
            )
            
            // Button Text Color
            colorRow(
                title: "Button Text",
                color: $buttonTextColorValue,
                hexBinding: $buttonTextColor
            )
        }
        .onAppear {
            if let hex = wallpaperColor {
                wallpaperColorValue = Color(hex: hex)
            }
            if let hex = titleColor {
                titleColorValue = Color(hex: hex)
            }
            if let hex = pageTextColor {
                pageTextColorValue = Color(hex: hex)
            }
            if let hex = buttonColor {
                buttonColorValue = Color(hex: hex)
            }
            if let hex = buttonTextColor {
                buttonTextColorValue = Color(hex: hex)
            }
        }
    }
    
    private func colorRow(title: String, color: Binding<Color>, hexBinding: Binding<String?>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.text)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            SwiftUI.ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 44)
                .onChange(of: color.wrappedValue) { newColor in
                    hexBinding.wrappedValue = hexString(from: newColor)
                }
        }
        .padding(12)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    DesignerColorPicker(
        wallpaperColor: .constant(nil),
        titleColor: .constant(nil),
        pageTextColor: .constant(nil),
        buttonColor: .constant(nil),
        buttonTextColor: .constant(nil)
    )
    .padding()
}

