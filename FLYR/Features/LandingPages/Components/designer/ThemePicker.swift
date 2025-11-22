import SwiftUI

struct ThemePicker: View {
    @Binding var selectedTheme: String
    let themes = LandingPageTheme.allCases.filter { $0 != .custom }
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(themes) { theme in
                ThemeCard(
                    theme: theme,
                    isSelected: selectedTheme == theme.rawValue
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTheme = theme.rawValue
                    }
                }
            }
        }
    }
}

struct ThemeCard: View {
    let theme: LandingPageTheme
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Preview background
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: theme.previewGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 80)
                    .overlay(
                        // Text sample
                        VStack(spacing: 4) {
                            Text("Sample")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(Color(hex: theme.defaultTitleColor))
                            Text("Text")
                                .font(.system(size: 10, weight: .regular, design: .default))
                                .foregroundColor(Color(hex: theme.defaultTextColor))
                        }
                    )
                    .overlay(
                        // Corner radius indicator
                        RoundedRectangle(cornerRadius: theme.defaultButtonCornerRadius)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .padding(8)
                    )
                
                // Theme name
                Text(theme.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.text)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accent : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 8 : 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ThemePicker(selectedTheme: .constant("Air"))
        .padding()
}


