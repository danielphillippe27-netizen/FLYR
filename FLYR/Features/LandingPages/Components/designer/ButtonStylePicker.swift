import SwiftUI

struct ButtonStylePicker: View {
    @Binding var buttonStyle: String
    @Binding var buttonCornerRadius: Double
    
    let buttonStyles = ["Solid", "Glass", "Outline"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Button Style
            VStack(alignment: .leading, spacing: 12) {
                Text("Button Style")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.muted)
                
                Picker("Button Style", selection: $buttonStyle) {
                    ForEach(buttonStyles, id: \.self) { style in
                        Text(style).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Corner Radius Slider
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Corner Radius")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.muted)
                    
                    Spacer()
                    
                    Text("\(Int(buttonCornerRadius))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.text)
                        .monospacedDigit()
                }
                
                Slider(value: $buttonCornerRadius, in: 0...30, step: 1)
                    .tint(.accent)
                
                // Preview
                HStack(spacing: 8) {
                    Text("Preview:")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                    
                    Spacer()
                    
                    // Solid preview
                    if buttonStyle == "Solid" {
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .fill(Color.accent)
                            .frame(width: 80, height: 36)
                    }
                    // Glass preview
                    else if buttonStyle == "Glass" {
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: buttonCornerRadius)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .frame(width: 80, height: 36)
                    }
                    // Outline preview
                    else {
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: buttonCornerRadius)
                                    .stroke(Color.accent, lineWidth: 2)
                            )
                            .frame(width: 80, height: 36)
                    }
                }
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

#Preview {
    ButtonStylePicker(
        buttonStyle: .constant("Solid"),
        buttonCornerRadius: .constant(12.0)
    )
    .padding()
}


