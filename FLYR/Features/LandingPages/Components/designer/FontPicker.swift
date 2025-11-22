import SwiftUI

struct FontPicker: View {
    @Binding var titleFont: String
    @Binding var bodyFont: String
    @Binding var titleSize: String
    
    let availableFonts = ["SF Pro", "Rounded", "Calistoga", "Inter", "Poppins", "Serif Pro"]
    let titleSizes = ["Small", "Large"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title Font
            VStack(alignment: .leading, spacing: 12) {
                Text("Title Font")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.muted)
                
                Picker("Title Font", selection: $titleFont) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .pickerStyle(.menu)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Body Font
            VStack(alignment: .leading, spacing: 12) {
                Text("Body Font")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.muted)
                
                Picker("Body Font", selection: $bodyFont) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .pickerStyle(.menu)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Title Size
            VStack(alignment: .leading, spacing: 12) {
                Text("Title Size")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.muted)
                
                Picker("Title Size", selection: $titleSize) {
                    ForEach(titleSizes, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

#Preview {
    FontPicker(
        titleFont: .constant("SF Pro"),
        bodyFont: .constant("SF Pro"),
        titleSize: .constant("Large")
    )
    .padding()
}


