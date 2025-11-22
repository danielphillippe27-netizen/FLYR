import SwiftUI

/// A reusable profile avatar component that displays a user's avatar image or initials
struct ProfileAvatarView: View {
    let avatarUrl: String?
    let name: String
    let size: CGFloat
    
    private var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            let first = String(components[0].prefix(1))
            let last = String(components[components.count - 1].prefix(1))
            return (first + last).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    private var backgroundColor: Color {
        // Generate a consistent color based on the name
        let hash = name.hashValue
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .red, .teal, .indigo
        ]
        return colors[abs(hash) % colors.count].opacity(0.7)
    }
    
    var body: some View {
        Group {
            if let avatarUrl = avatarUrl, !avatarUrl.isEmpty {
                AsyncImage(url: URL(string: avatarUrl)) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
    
    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ProfileAvatarView(
            avatarUrl: nil,
            name: "John Doe",
            size: 60
        )
        
        ProfileAvatarView(
            avatarUrl: nil,
            name: "Jane Smith",
            size: 80
        )
        
        ProfileAvatarView(
            avatarUrl: nil,
            name: "Bob",
            size: 100
        )
    }
    .padding()
    .background(Color.bg)
}


